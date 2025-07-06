#!/bin/bash
# CI Monitor Hook - Monitors GitHub Actions CI status after push completion

set -euo pipefail

# Source shared utilities
source "$(dirname "$0")/shared-utils.sh"

# Configuration
MAX_WAIT_TIME=300 # Maximum wait time in seconds (5 minutes)
INITIAL_DELAY=5   # Initial delay between checks in seconds
MAX_DELAY=30      # Maximum delay between checks in seconds

# Read input
INPUT=$(cat)

# Extract transcript path
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    # No transcript path or file doesn't exist, exit normally
    exit 0
fi

# Check if last Claude message contains "REVIEW_COMPLETED && PUSH_COMPLETED"
LAST_MESSAGE=$(extract_last_assistant_message "$TRANSCRIPT_PATH" 0 true)

if [ -z "$LAST_MESSAGE" ] || ! echo "$LAST_MESSAGE" | grep -q "REVIEW_COMPLETED && PUSH_COMPLETED"; then
    # Message not found, exit normally
    exit 0
fi

# Function to get current branch
get_current_branch() {
    git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main"
}

# Function to get latest workflow run for current branch
get_latest_workflow_run() {
    local branch="$1"

    # Get workflow runs for the current branch
    if ! gh run list --branch "$branch" --limit 1 --json status,conclusion,databaseId,name,headSha,url 2>/dev/null; then
        return 1
    fi
}

# Function to get workflow run details
get_workflow_run_details() {
    local run_id="$1"

    if ! gh run view "$run_id" --json status,conclusion,jobs 2>/dev/null; then
        return 1
    fi
}

# Function to format CI failure details
format_ci_failure() {
    local run_data="$1"
    local run_url=$(echo "$run_data" | jq -r '.[0].url // "Unknown"')
    local run_name=$(echo "$run_data" | jq -r '.[0].name // "Unknown workflow"')
    local conclusion=$(echo "$run_data" | jq -r '.[0].conclusion // "failure"')

    cat <<EOF
## CI Check Failed

**Workflow:** $run_name
**Status:** $conclusion
**URL:** $run_url

The GitHub Actions CI check has failed. Please review the failure details and fix any issues before continuing.

### Next Steps:
1. Click the URL above to view the detailed failure logs
2. Fix the identified issues in your code
3. Commit and push the fixes
4. The CI will automatically re-run

Would you like me to help analyze and fix the CI failures?
EOF
}

# Main monitoring logic
monitor_ci() {
    local branch=$(get_current_branch)
    local start_time=$(date +%s)
    local delay=$INITIAL_DELAY
    local last_run_id=""

    echo "Monitoring CI status for branch: $branch" >&2

    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        # Check if we've exceeded max wait time
        if [ $elapsed -ge $MAX_WAIT_TIME ]; then
            echo "CI monitoring timeout reached after ${MAX_WAIT_TIME}s" >&2
            exit 0
        fi

        # Get latest workflow run
        local run_data
        if ! run_data=$(get_latest_workflow_run "$branch"); then
            echo "Warning: Failed to fetch workflow runs (network error)" >&2
            sleep $delay
            # Increase delay with exponential backoff
            delay=$((delay * 2))
            [ $delay -gt $MAX_DELAY ] && delay=$MAX_DELAY
            continue
        fi

        # Check if there are any runs
        if [ "$(echo "$run_data" | jq '. | length')" -eq 0 ]; then
            echo "No workflow runs found for branch $branch" >&2
            sleep $delay
            continue
        fi

        # Get run details
        local run_id=$(echo "$run_data" | jq -r '.[0].databaseId')
        local status=$(echo "$run_data" | jq -r '.[0].status')
        local conclusion=$(echo "$run_data" | jq -r '.[0].conclusion // "null"')

        # Check if this is a new run
        if [ "$run_id" != "$last_run_id" ]; then
            last_run_id="$run_id"
            echo "Found workflow run: $run_id (status: $status)" >&2
        fi

        # Check run status
        case "$status" in
        "completed")
            case "$conclusion" in
            "success")
                echo "CI passed successfully!" >&2
                exit 0
                ;;
            "failure" | "cancelled" | "timed_out")
                # CI failed, format and return decision block
                local failure_message=$(format_ci_failure "$run_data")
                local escaped_message=$(echo "$failure_message" | jq -Rs .)

                cat <<EOF
{
  "decision": "block",
  "reason": $escaped_message
}
EOF
                exit 0
                ;;
            *)
                # Other conclusion, continue monitoring
                ;;
            esac
            ;;
        "in_progress" | "queued" | "requested" | "waiting" | "pending")
            # Still running, continue monitoring
            ;;
        *)
            echo "Unknown workflow status: $status" >&2
            ;;
        esac

        # Wait before next check
        sleep $delay

        # Reset delay to initial value on successful API call
        delay=$INITIAL_DELAY
    done
}

# Check if gh CLI is available
if ! command -v gh &>/dev/null; then
    echo "Warning: GitHub CLI (gh) not found. CI monitoring disabled." >&2
    exit 0
fi

# Check if we're authenticated with gh
if ! gh auth status &>/dev/null; then
    echo "Warning: Not authenticated with GitHub CLI. CI monitoring disabled." >&2
    exit 0
fi

# Check if we're in a git repository
if ! git rev-parse --git-dir &>/dev/null; then
    echo "Warning: Not in a git repository. CI monitoring disabled." >&2
    exit 0
fi

# Start monitoring
monitor_ci

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

# Function to get active workflow runs for current branch
get_active_workflow_runs() {
    local branch="$1"

    # Get all active workflow runs for the current branch (in_progress, queued, etc.)
    if ! gh run list --branch "$branch" --limit 10 --json status,conclusion,databaseId,name,headSha,url 2>/dev/null; then
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

    echo "Monitoring CI status for branch: $branch" >&2
    local log_dir
    log_dir=$(mktemp -d)
    echo "Monitoring CI status for branch: $branch" > "$log_dir/ci_monitor.log"

    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        # Check if we've exceeded max wait time
        if [ $elapsed -ge $MAX_WAIT_TIME ]; then
            echo "CI monitoring timeout reached after ${MAX_WAIT_TIME}s" >&2
            echo "CI monitoring timeout reached after ${MAX_WAIT_TIME}s" > "$log_dir/ci_monitor.log"
            exit 0
        fi

        # Get workflow runs
        local run_data
        if ! run_data=$(get_active_workflow_runs "$branch"); then
            echo "Warning: Failed to fetch workflow runs (network error)" >&2
            echo "Warning: Failed to fetch workflow runs (network error)" > "$log_dir/ci_monitor.log"
            sleep $delay
            # Increase delay with exponential backoff
            delay=$((delay * 2))
            [ $delay -gt $MAX_DELAY ] && delay=$MAX_DELAY
            continue
        fi

        # Check if there are any runs
        if [ "$(echo "$run_data" | jq '. | length')" -eq 0 ]; then
            echo "No workflow runs found for branch $branch" >&2
            echo "No workflow runs found for branch $branch" > "$log_dir/ci_monitor.log"
            sleep $delay
            continue
        fi

        # Check all workflow runs status
        local all_completed=true
        local any_failed=false
        local failed_runs=()
        
        while IFS= read -r run; do
            local run_id=$(echo "$run" | jq -r '.databaseId')
            local status=$(echo "$run" | jq -r '.status')
            local conclusion=$(echo "$run" | jq -r '.conclusion // "null"')
            
            case "$status" in
            "completed")
                case "$conclusion" in
                "success")
                    # This run passed, continue checking others
                    ;;
                "failure" | "cancelled" | "timed_out")
                    any_failed=true
                    failed_runs+=("$run")
                    ;;
                *)
                    # Other conclusion (e.g., skipped), continue monitoring
                    all_completed=false
                    ;;
                esac
                ;;
            "in_progress" | "queued" | "requested" | "waiting" | "pending")
                all_completed=false
                ;;
            *)
                echo "Unknown workflow status: $status for run $run_id" >&2
                echo "Unknown workflow status: $status for run $run_id" > "$log_dir/ci_monitor.log"
                all_completed=false
                ;;
            esac
        done < <(echo "$run_data" | jq -c '.[]')

        # If any runs failed, report failure
        if [ "$any_failed" = true ]; then
            # Format failure message using the first failed run
            local failure_message=$(format_ci_failure "$(echo "${failed_runs[0]}" | jq -s '.')")
            local escaped_message=$(echo "$failure_message" | jq -Rs .)

            cat <<EOF
{
  "decision": "block",
  "reason": $escaped_message
}
EOF
            exit 0
        fi

        # If all runs are completed and none failed, success
        if [ "$all_completed" = true ]; then
            echo "All CI workflows passed successfully!" >&2
            echo "All CI workflows passed successfully!" > "$log_dir/ci_monitor.log"
            exit 0
        fi

        # Some runs are still in progress, continue monitoring
        echo "Some workflows still in progress, continuing to monitor..." >&2
        echo "Some workflows still in progress, continuing to monitor..." > "$log_dir/ci_monitor.log"

        # Wait before next check
        sleep $delay

        # Reset delay to initial value on successful API call
        delay=$INITIAL_DELAY
    done
}

# Check if gh CLI is available
if ! command -v gh &>/dev/null; then
    echo "Warning: GitHub CLI (gh) not found. CI monitoring disabled." >&2
    log_warning "GitHub CLI (gh) not found. CI monitoring disabled."
    exit 0
fi

# Check if we're authenticated with gh
if ! gh auth status &>/dev/null; then
    echo "Warning: Not authenticated with GitHub CLI. CI monitoring disabled." >&2
    log_warning "Not authenticated with GitHub CLI. CI monitoring disabled."
    exit 0
fi

# Check if we're in a git repository
if ! git rev-parse --git-dir &>/dev/null; then
    echo "Warning: Not in a git repository. CI monitoring disabled." >&2
    log_warning "Not in a git repository. CI monitoring disabled."
    exit 0
fi

# Start monitoring
monitor_ci

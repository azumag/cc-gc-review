#!/bin/bash
# CI Monitor Hook - Monitors GitHub Actions CI status after push completion

set -euo pipefail

# Parse command line arguments
DEBUG_MODE=false
while [[ $# -gt 0 ]]; do
    case $1 in
    --debug)
        DEBUG_MODE=true
        shift
        ;;
    *)
        # Unknown option, ignore and pass through
        shift
        ;;
    esac
done

# Source shared utilities
source "$(dirname "$0")/shared-utils.sh"

# Configuration
MAX_WAIT_TIME=300 # Maximum wait time in seconds (5 minutes)
INITIAL_DELAY=5   # Initial delay between checks in seconds
MAX_DELAY=30      # Maximum delay between checks in seconds

# Debug log configuration (only when debug mode is enabled)
if [ "$DEBUG_MODE" = "true" ]; then
    readonly LOG_DIR="/tmp"
    readonly LOG_FILE="${LOG_DIR}/ci-monitor-hook.log"
    readonly ERROR_LOG_FILE="${LOG_DIR}/ci-monitor-error.log"
    # Output log directory for user reference
    echo "[ci-monitor-hook] Debug logging enabled. Logs will be written to: $LOG_DIR" >&2
fi

# Logging function with level support
log_message() {
    local level="$1"
    local stage="$2"
    local message="$3"

    # Always log errors and warnings to /tmp for debugging, even when debug mode is off
    local timestamp
    timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    local log_entry="$timestamp [$level] [$stage] $message"

    if [ "$DEBUG_MODE" = "true" ]; then
        # Log to main log file
        echo "$log_entry" >>"$LOG_FILE"

        # Log errors to separate error log
        if [ "$level" = "ERROR" ]; then
            echo "$log_entry" >>"$ERROR_LOG_FILE"
        fi

        # Also output to stderr for immediate visibility in debug mode
        echo "$log_entry" >&2
    else
        # Even without debug mode, log errors and warnings for troubleshooting
        if [ "$level" = "ERROR" ] || [ "$level" = "WARN" ]; then
            echo "$log_entry" >>"/tmp/ci-monitor-hook-error.log"
        fi
    fi
}

# Convenience functions for different log levels
debug_log() { log_message "DEBUG" "$1" "$2"; }
info_log() { log_message "INFO" "$1" "$2"; }
warn_log() { log_message "WARN" "$1" "$2"; }
error_log() { log_message "ERROR" "$1" "$2"; }


# Read input
INPUT=$(cat)
info_log "START" "Script started, input received"
info_log "INPUT" "Received input: $INPUT"

# Extract session_id and transcript_path
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')
debug_log "TRANSCRIPT" "Processing session_id: $SESSION_ID"
debug_log "TRANSCRIPT" "Processing transcript path: $TRANSCRIPT_PATH"
debug_log "TRANSCRIPT" "Raw input JSON: $INPUT"
debug_log "TRANSCRIPT" "File existence check: $(test -f "$TRANSCRIPT_PATH" && echo "EXISTS" || echo "NOT_FOUND")"

# Validate session ID consistency
validate_session_id() {
    local expected_session_id="$1"
    local transcript_path="$2"
    
    # Extract session ID from transcript path
    local path_session_id
    path_session_id=$(basename "$transcript_path" .jsonl)
    
    debug_log "SESSION_VALIDATION" "Expected session ID: $expected_session_id"
    debug_log "SESSION_VALIDATION" "Path-derived session ID: $path_session_id"
    
    if [ "$expected_session_id" != "$path_session_id" ]; then
        warn_log "SESSION_VALIDATION" "Session ID mismatch: expected=$expected_session_id, path=$path_session_id"
        return 1
    fi
    
    debug_log "SESSION_VALIDATION" "Session ID validation passed"
    return 0
}

# Handle backwards compatibility - if session_id is not provided, derive it from transcript path
if [ -z "$SESSION_ID" ] || [ "$SESSION_ID" = "null" ]; then
    if [ -n "$TRANSCRIPT_PATH" ] && [ "$TRANSCRIPT_PATH" != "null" ]; then
        SESSION_ID=$(basename "$TRANSCRIPT_PATH" .jsonl)
        debug_log "SESSION" "Session ID derived from transcript path: $SESSION_ID"
    else
        warn_log "SESSION" "No session ID or transcript path provided, skipping monitoring"
        echo "[ci-monitor-hook] Warning: No session ID or transcript path provided, skipping monitoring" >&2
        safe_exit "No session ID or transcript path provided, monitoring skipped" "approve"
    fi
fi

if [ -z "$TRANSCRIPT_PATH" ] || [ "$TRANSCRIPT_PATH" = "null" ]; then
    warn_log "TRANSCRIPT" "Transcript path is null or empty, skipping monitoring"
    echo "[ci-monitor-hook] Warning: No transcript path provided, skipping monitoring" >&2
    safe_exit "No transcript path provided, monitoring skipped" "approve"
fi

# Only validate session ID consistency if we have both session_id and transcript_path from input
if echo "$INPUT" | jq -e '.session_id' >/dev/null 2>&1; then
    if ! validate_session_id "$SESSION_ID" "$TRANSCRIPT_PATH"; then
        warn_log "SESSION_VALIDATION" "Session ID validation failed, attempting to find correct transcript"
        echo "[ci-monitor-hook] Warning: Session ID mismatch detected" >&2
        
        # Try to find the correct transcript file for this session
        TRANSCRIPT_DIR=$(dirname "$TRANSCRIPT_PATH")
        CORRECT_TRANSCRIPT="$TRANSCRIPT_DIR/$SESSION_ID.jsonl"
        
        if [ -f "$CORRECT_TRANSCRIPT" ]; then
            warn_log "SESSION_VALIDATION" "Found correct transcript for session: $CORRECT_TRANSCRIPT"
            echo "[ci-monitor-hook] Using correct transcript file: $CORRECT_TRANSCRIPT" >&2
            TRANSCRIPT_PATH="$CORRECT_TRANSCRIPT"
        else
            warn_log "SESSION_VALIDATION" "Correct transcript not found: $CORRECT_TRANSCRIPT"
            echo "[ci-monitor-hook] Warning: Correct transcript file not found, will continue with original path" >&2
        fi
    fi
else
    debug_log "SESSION_VALIDATION" "No session_id in input, skipping validation (backwards compatibility)"
fi

# Wait for transcript file to be created (up to 10 seconds)
WAIT_COUNT=0
MAX_WAIT=10
while [ ! -f "$TRANSCRIPT_PATH" ] && [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    debug_log "TRANSCRIPT" "Waiting for transcript file to be created (attempt $((WAIT_COUNT + 1))/$MAX_WAIT)"
    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
done

# If file still doesn't exist after waiting, try to find the latest transcript file
if [ ! -f "$TRANSCRIPT_PATH" ]; then
    warn_log "TRANSCRIPT" "Specified transcript file not found: '$TRANSCRIPT_PATH'"
    
    # Try to find the latest transcript file in the same directory
    TRANSCRIPT_DIR=$(dirname "$TRANSCRIPT_PATH")
    if [ -d "$TRANSCRIPT_DIR" ]; then
        LATEST_TRANSCRIPT=$(find "$TRANSCRIPT_DIR" -name "*.jsonl" -type f -exec stat -f "%m %N" {} \; 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
        if [ -n "$LATEST_TRANSCRIPT" ] && [ -f "$LATEST_TRANSCRIPT" ]; then
            warn_log "TRANSCRIPT" "Using latest transcript file instead: '$LATEST_TRANSCRIPT'"
            echo "[ci-monitor-hook] Warning: Using latest transcript file: '$LATEST_TRANSCRIPT'" >&2
            TRANSCRIPT_PATH="$LATEST_TRANSCRIPT"
        else
            warn_log "TRANSCRIPT" "No transcript files found in directory: '$TRANSCRIPT_DIR'"
            echo "[ci-monitor-hook] Warning: No transcript files found, skipping monitoring" >&2
            safe_exit "No transcript files found, monitoring skipped" "approve"
        fi
    else
        warn_log "TRANSCRIPT" "Transcript directory not found: '$TRANSCRIPT_DIR'"
        echo "[ci-monitor-hook] Warning: Transcript directory not found, skipping monitoring" >&2
        safe_exit "Transcript directory not found, monitoring skipped" "approve"
    fi
fi

debug_log "TRANSCRIPT" "Transcript file found after ${WAIT_COUNT}s wait"

# Check if last Claude message contains "REVIEW_COMPLETED && PUSH_COMPLETED"
if [ -f "$TRANSCRIPT_PATH" ]; then
    debug_log "TRANSCRIPT" "Transcript file found, extracting last messages"
    debug_log "TRANSCRIPT" "File size: $(wc -l < "$TRANSCRIPT_PATH") lines"
    debug_log "TRANSCRIPT" "File last modified: $(stat -f "%Sm" "$TRANSCRIPT_PATH")"
    
    LAST_MESSAGE=$(extract_last_assistant_message "$TRANSCRIPT_PATH" 0 true)
    debug_log "TRANSCRIPT" "Extracted message length: ${#LAST_MESSAGE} characters"
    
    if [ -z "$LAST_MESSAGE" ]; then
        debug_log "TRANSCRIPT" "No assistant messages found in transcript"
        # Try to check what's actually in the file
        debug_log "TRANSCRIPT" "Last 3 lines of transcript:"
        tail -3 "$TRANSCRIPT_PATH" | while read -r line; do
            debug_log "TRANSCRIPT" "Line: $line"
        done
        exit 0
    else
        debug_log "TRANSCRIPT" "First 100 chars of extracted message: ${LAST_MESSAGE:0:100}"
    fi
    
    if ! echo "$LAST_MESSAGE" | grep -q "REVIEW_COMPLETED && PUSH_COMPLETED"; then
        debug_log "TRANSCRIPT" "REVIEW_COMPLETED && PUSH_COMPLETED marker not found, exiting"
        safe_exit "REVIEW_COMPLETED && PUSH_COMPLETED marker not found" "approve"
    fi
    
    debug_log "TRANSCRIPT" "Found REVIEW_COMPLETED && PUSH_COMPLETED marker, continuing"
else
    debug_log "TRANSCRIPT" "Transcript file not found or not accessible"
    safe_exit "Transcript file not found or not accessible" "approve"
fi

# Function to get current branch
get_current_branch() {
    git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main"
}

# Function to get active workflow runs for current branch and commit
get_active_workflow_runs() {
    local branch="$1"
    local current_sha
    current_sha=$(git rev-parse HEAD)

    # Get all workflow runs for the current branch and filter by current commit
    if ! gh run list --branch "$branch" --limit 20 --json status,conclusion,databaseId,name,headSha,url 2>/dev/null |
        jq --arg sha "$current_sha" '[.[] | select(.headSha == $sha)]'; then
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
    local run_url
    run_url=$(echo "$run_data" | jq -r '.[0].url // "Unknown"')
    local run_name
    run_name=$(echo "$run_data" | jq -r '.[0].name // "Unknown workflow"')
    local conclusion
    conclusion=$(echo "$run_data" | jq -r '.[0].conclusion // "failure"')

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
    local branch
    branch=$(get_current_branch)
    local start_time
    start_time=$(date +%s)
    local delay=$INITIAL_DELAY

    echo "Monitoring CI status for branch: $branch" >&2
    local log_dir
    log_dir=$(mktemp -d)
    echo "Monitoring CI status for branch: $branch" >"$log_dir/ci_monitor.log"

    while true; do
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        # Check if we've exceeded max wait time
        if [ $elapsed -ge $MAX_WAIT_TIME ]; then
            echo "CI monitoring timeout reached after ${MAX_WAIT_TIME}s" >&2
            echo "CI monitoring timeout reached after ${MAX_WAIT_TIME}s" >"$log_dir/ci_monitor.log"
            safe_exit "CI monitoring timeout reached after ${MAX_WAIT_TIME}s" "block"
        fi

        # Get workflow runs
        local run_data
        if ! run_data=$(get_active_workflow_runs "$branch"); then
            echo "Warning: Failed to fetch workflow runs (network error)" >&2
            echo "Warning: Failed to fetch workflow runs (network error)" >"$log_dir/ci_monitor.log"
            sleep $delay
            # Increase delay with exponential backoff
            delay=$((delay * 2))
            [ $delay -gt $MAX_DELAY ] && delay=$MAX_DELAY
            continue
        fi

        # Check if there are any runs
        if [ "$(echo "$run_data" | jq '. | length')" -eq 0 ]; then
            echo "No workflow runs found for branch $branch" >&2
            echo "No workflow runs found for branch $branch" >"$log_dir/ci_monitor.log"
            sleep $delay
            continue
        fi

        # Check all workflow runs status
        local all_completed=true
        local any_failed=false
        local failed_runs=()

        while IFS= read -r run; do
            local run_id
            run_id=$(echo "$run" | jq -r '.databaseId')
            local status
            status=$(echo "$run" | jq -r '.status')
            local conclusion
            conclusion=$(echo "$run" | jq -r '.conclusion // "null"')

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
                echo "Unknown workflow status: $status for run $run_id" >"$log_dir/ci_monitor.log"
                all_completed=false
                ;;
            esac
        done < <(echo "$run_data" | jq -c '.[]')

        # If any runs failed, report failure
        if [ "$any_failed" = true ]; then
            # Format failure message using the first failed run
            local failure_message
            failure_message=$(format_ci_failure "$(echo "${failed_runs[0]}" | jq -s '.')")
            local escaped_message
            escaped_message=$(echo "$failure_message" | jq -Rs .)

            cat <<EOF
{
  "decision": "block",
  "reason": $escaped_message
}
EOF
            return 0
        fi

        # If all runs are completed and none failed, success
        if [ "$all_completed" = true ]; then
            echo "All CI workflows passed successfully!" >&2
            echo "All CI workflows passed successfully!" >"$log_dir/ci_monitor.log"
            safe_exit "All CI workflows passed successfully!" "approve"
        fi

        # Some runs are still in progress, continue monitoring
        echo "Some workflows still in progress, continuing to monitor..." >&2
        echo "Some workflows still in progress, continuing to monitor..." >"$log_dir/ci_monitor.log"

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
    safe_exit "GitHub CLI (gh) not found. CI monitoring disabled." "approve"
fi

# Check if we're authenticated with gh
if ! gh auth status &>/dev/null; then
    echo "Warning: Not authenticated with GitHub CLI. CI monitoring disabled." >&2
    log_warning "Not authenticated with GitHub CLI. CI monitoring disabled."
    safe_exit "Not authenticated with GitHub CLI. CI monitoring disabled." "approve"
fi

# Check if we're in a git repository
if ! git rev-parse --git-dir &>/dev/null; then
    echo "Warning: Not in a git repository. CI monitoring disabled." >&2
    log_warning "Not in a git repository. CI monitoring disabled."
    safe_exit "Not in a git repository. CI monitoring disabled." "approve"
fi

# Start monitoring
monitor_ci

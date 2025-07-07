#!/bin/bash

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

# Debug log configuration (only when debug mode is enabled)
if [ "$DEBUG_MODE" = "true" ]; then
    readonly LOG_DIR="/tmp"
    readonly LOG_FILE="${LOG_DIR}/push-review-complete.log"
    readonly ERROR_LOG_FILE="${LOG_DIR}/push-review-complete-error.log"
    # Output log directory for user reference
    echo "[push-review-complete] Debug logging enabled. Logs will be written to: $LOG_DIR" >&2
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
            echo "$log_entry" >>"/tmp/push-review-complete-error.log"
        fi
    fi
}

# Convenience functions for different log levels
debug_log() { log_message "DEBUG" "$1" "$2"; }
info_log() { log_message "INFO" "$1" "$2"; }
warn_log() { log_message "WARN" "$1" "$2"; }
error_log() { log_message "ERROR" "$1" "$2"; }

INPUT=$(cat)
info_log "START" "Script started, input received"
info_log "INPUT" "Received input: $INPUT"

PRINCIPLES=$(
    cat <<'EOF'
## 原則
- 作業ディレクトリにおいて、commit していないファイルがあればコミットし、pushせよ
- すべてpush済みならば、REVIEW_COMPLETED && PUSH_COMPLETED と発言せよ
----
EOF
)

ESCAPED_PRINCIPLES=$(echo "$PRINCIPLES" | jq -Rs .)

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
        warn_log "SESSION" "No session ID or transcript path provided, skipping push check"
        echo "[push-review-complete] Warning: No session ID or transcript path provided, skipping push check" >&2
        safe_exit "No session ID or transcript path provided, push check skipped" "approve"
    fi
fi

if [ -z "$TRANSCRIPT_PATH" ] || [ "$TRANSCRIPT_PATH" = "null" ]; then
    warn_log "TRANSCRIPT" "Transcript path is null or empty, skipping push check"
    echo "[push-review-complete] Warning: No transcript path provided, skipping push check" >&2
    safe_exit "No transcript path provided, push check skipped" "approve"
fi

# Only validate session ID consistency if we have both session_id and transcript_path from input
if echo "$INPUT" | jq -e '.session_id' >/dev/null 2>&1; then
    if ! validate_session_id "$SESSION_ID" "$TRANSCRIPT_PATH"; then
        warn_log "SESSION_VALIDATION" "Session ID validation failed, attempting to find correct transcript"
        echo "[push-review-complete] Warning: Session ID mismatch detected" >&2
        
        # Try to find the correct transcript file for this session
        TRANSCRIPT_DIR=$(dirname "$TRANSCRIPT_PATH")
        CORRECT_TRANSCRIPT="$TRANSCRIPT_DIR/$SESSION_ID.jsonl"
        
        if [ -f "$CORRECT_TRANSCRIPT" ]; then
            warn_log "SESSION_VALIDATION" "Found correct transcript for session: $CORRECT_TRANSCRIPT"
            echo "[push-review-complete] Using correct transcript file: $CORRECT_TRANSCRIPT" >&2
            TRANSCRIPT_PATH="$CORRECT_TRANSCRIPT"
        else
            warn_log "SESSION_VALIDATION" "Correct transcript not found: $CORRECT_TRANSCRIPT"
            echo "[push-review-complete] Warning: Correct transcript file not found, will continue with original path" >&2
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
            echo "[push-review-complete] Warning: Using latest transcript file: '$LATEST_TRANSCRIPT'" >&2
            TRANSCRIPT_PATH="$LATEST_TRANSCRIPT"
        else
            warn_log "TRANSCRIPT" "No transcript files found in directory: '$TRANSCRIPT_DIR'"
            echo "[push-review-complete] Warning: No transcript files found, skipping push check" >&2
            safe_exit "No transcript files found, push check skipped" "approve"
        fi
    else
        warn_log "TRANSCRIPT" "Transcript directory not found: '$TRANSCRIPT_DIR'"
        echo "[push-review-complete] Warning: Transcript directory not found, skipping push check" >&2
        safe_exit "Transcript directory not found, push check skipped" "approve"
    fi
fi

debug_log "TRANSCRIPT" "Transcript file found after ${WAIT_COUNT}s wait"
if [ -f "$TRANSCRIPT_PATH" ]; then
    debug_log "TRANSCRIPT" "Transcript file found, extracting last messages"
    debug_log "TRANSCRIPT" "File size: $(wc -l < "$TRANSCRIPT_PATH") lines"
    debug_log "TRANSCRIPT" "File last modified: $(stat -f "%Sm" "$TRANSCRIPT_PATH")"
    
    LAST_MESSAGES=$(extract_last_assistant_message "$TRANSCRIPT_PATH" 0 true)
    debug_log "TRANSCRIPT" "Extracted message length: ${#LAST_MESSAGES} characters"
    
    if [ -z "$LAST_MESSAGES" ]; then
        debug_log "TRANSCRIPT" "No assistant messages found in transcript"
        # Try to check what's actually in the file
        debug_log "TRANSCRIPT" "Last 3 lines of transcript:"
        tail -3 "$TRANSCRIPT_PATH" | while read -r line; do
            debug_log "TRANSCRIPT" "Line: $line"
        done
        safe_exit "No assistant messages found in transcript" "approve"
    else
        debug_log "TRANSCRIPT" "First 100 chars of extracted message: ${LAST_MESSAGES:0:100}"
    fi
    
    # REVIEW_COMPLETED && PUSH_COMPLETEDが含まれている場合は終了
    if [ -n "$LAST_MESSAGES" ] && echo "$LAST_MESSAGES" | grep -q "REVIEW_COMPLETED && PUSH_COMPLETED"; then
        debug_log "TRANSCRIPT" "Found REVIEW_COMPLETED && PUSH_COMPLETED marker, exiting"
        safe_exit "Push already completed" "approve"
    fi

    if [ -n "$LAST_MESSAGES" ] && echo "$LAST_MESSAGES" | grep -q "REVIEW_COMPLETED"; then
        debug_log "TRANSCRIPT" "Found REVIEW_COMPLETED marker, triggering push"
        cat <<EOF
{
  "decision": "block",
  "reason": $ESCAPED_PRINCIPLES
}
EOF
        exit 0
    fi
    
    debug_log "TRANSCRIPT" "No trigger conditions found, exiting"
    safe_exit "No push trigger found" "approve"
else
    debug_log "TRANSCRIPT" "Transcript file not found or not accessible"
    safe_exit "Transcript file not found or not accessible" "approve"
fi

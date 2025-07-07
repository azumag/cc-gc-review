#!/bin/bash

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

# Configuration constants
readonly CLAUDE_SUMMARY_MAX_LENGTH=1000
readonly CLAUDE_SUMMARY_PRESERVE_LENGTH=400
readonly GEMINI_TIMEOUT=300

# Debug log configuration (only when debug mode is enabled)
if [ "$DEBUG_MODE" = "true" ]; then
    readonly LOG_DIR="/tmp"
    readonly LOG_FILE="${LOG_DIR}/gemini-review-hook.log"
    readonly ERROR_LOG_FILE="${LOG_DIR}/gemini-review-error.log"
fi

# Cleanup function for temporary files
cleanup() {
    [ -n "${TEMP_STDOUT:-}" ] && rm -f "$TEMP_STDOUT"
    [ -n "${TEMP_STDERR:-}" ] && rm -f "$TEMP_STDERR"

    # Clean up debug log files (only if debug mode was enabled)
    if [ "${DEBUG_GEMINI_HOOK:-false}" = "true" ]; then
        local log_dir="${GEMINI_HOOK_LOG_DIR:-/tmp}"
        rm -f "$log_dir/gemini-review-hook-$$.log" "$log_dir/gemini-review-error-$$.log" "$log_dir/gemini-review-debug-$$.log"
    fi
}

# Logging function with level support
log_message() {
    local level="$1"
    local stage="$2"
    local message="$3"
    
    # Only log when debug mode is enabled
    if [ "$DEBUG_MODE" = "true" ]; then
        local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
        local log_entry="$timestamp [$level] [$stage] $message"
        
        # Log to main log file
        echo "$log_entry" >> "$LOG_FILE"
        
        # Log errors to separate error log
        if [ "$level" = "ERROR" ]; then
            echo "$log_entry" >> "$ERROR_LOG_FILE"
        fi
        
        # Also output to stderr for immediate visibility in debug mode
        echo "$log_entry" >&2
    fi
}

# Convenience functions for different log levels
debug_log() { log_message "DEBUG" "$1" "$2"; }
info_log() { log_message "INFO" "$1" "$2"; }
warn_log() { log_message "WARN" "$1" "$2"; }
error_log() { log_message "ERROR" "$1" "$2"; }

# Set trap for cleanup on script exit
trap cleanup EXIT

INPUT=$(cat)
info_log "START" "Script started, input received"
info_log "INPUT" "Received input: $INPUT"

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path')
debug_log "TRANSCRIPT" "Processing transcript path: $TRANSCRIPT_PATH"
if [ -f "$TRANSCRIPT_PATH" ]; then
    debug_log "TRANSCRIPT" "Transcript file found, extracting last messages"
    LAST_MESSAGES=$(extract_last_assistant_message "$TRANSCRIPT_PATH" 100 false)
    if [ -n "$LAST_MESSAGES" ] && echo "$LAST_MESSAGES" | grep -q "REVIEW_COMPLETED"; then
        exit 0
    fi
    if [ -n "$LAST_MESSAGES" ] && echo "$LAST_MESSAGES" | grep -q "REVIEW_RATE_LIMITED"; then
        exit 0
    fi
    debug_log "TRANSCRIPT" "No exit conditions found, continuing"
else
    debug_log "TRANSCRIPT" "Transcript file not found or not accessible"
fi

PRINCIPLES=$(
    cat <<'EOF'
## 原則
Gemini のレビューにて改善点を指摘された場合は、その改善点に従って修正せよ。
これ以上の改善点は特に無しとレビューをもらったときのみ「REVIEW_COMPLETED」とだけ発言せよ。
レビュー内容が空、もしくは「REVIEW_RATE_LIMITED」とだけ書かれていた場合は、「REVIEW_RATE_LIMITED」とだけ発言せよ。
EOF
)

CLAUDE_SUMMARY=""
if [ -f "$TRANSCRIPT_PATH" ]; then
    debug_log "CLAUDE_SUMMARY" "Extracting Claude's last summary from transcript"
    # Extract Claude's last summary from transcript (JSONL format)
    # NOTE: This depends on Claude Code's transcript JSONL structure
    # If Claude Code changes its output format, this may need updates
    CLAUDE_SUMMARY=$(extract_last_assistant_message "$TRANSCRIPT_PATH" 0 true)

    # Check if extraction was successful
    if [ -z "$CLAUDE_SUMMARY" ]; then
        warn_log "CLAUDE_SUMMARY" "Failed to extract Claude summary (no assistant messages found)"
        echo "[gemini-review-hook] Warning: Failed to extract Claude summary from transcript (no assistant messages found)" >&2
    else
        debug_log "CLAUDE_SUMMARY" "Successfully extracted Claude summary (${#CLAUDE_SUMMARY} characters)"
    fi

    # Limit CLAUDE_SUMMARY to configured length to avoid token limit
    # Use character-aware truncation instead of byte-based to handle multibyte characters safely
    original_length=${#CLAUDE_SUMMARY}
    if [ "$original_length" -gt "$CLAUDE_SUMMARY_MAX_LENGTH" ]; then
        # Preserve important parts: first N chars + last N chars with separator
        FIRST_PART=$(printf "%.${CLAUDE_SUMMARY_PRESERVE_LENGTH}s" "$CLAUDE_SUMMARY")
        LAST_PART=$(echo "$CLAUDE_SUMMARY" | rev | cut -c1-${CLAUDE_SUMMARY_PRESERVE_LENGTH} | rev)
        CLAUDE_SUMMARY="${FIRST_PART}...(中略)...${LAST_PART}"
        debug_log "CLAUDE_SUMMARY" "Content truncated to preserve beginning and end (original: $original_length chars)"
    fi
fi

# Gather git information for review context
GIT_STATUS=""
GIT_DIFF=""
GIT_LOG=""

if git rev-parse --git-dir >/dev/null 2>&1; then
    debug_log "GIT" "Gathering git information for review context"

    # Get git status
    GIT_STATUS=$(git status --porcelain 2>/dev/null || echo "Unable to get git status")

    # Get recent changes (staged and unstaged)
    GIT_DIFF=$(git diff HEAD 2>/dev/null || echo "Unable to get git diff")
    if [ -z "$GIT_DIFF" ]; then
        # If no diff from HEAD, try staged changes
        GIT_DIFF=$(git diff --cached 2>/dev/null || echo "No staged changes")
    fi

    # Get recent commit log
    GIT_LOG=$(git log --oneline -n 3 2>/dev/null || echo "Unable to get git log")

    debug_log "GIT" "Git status length: ${#GIT_STATUS}, diff length: ${#GIT_DIFF}, log length: ${#GIT_LOG}"
else
    debug_log "GIT" "Not in a git repository"
fi

REVIEW_PROMPT=$(
    cat <<EOF
作業内容を厳正にレビューして、改善点を指摘してください。
以下に Git の情報が提供されない場合は、自ら git diff やコミット確認を行なって把握してください。

## Git の現在の状態:

### Git Status:
${GIT_STATUS}

### Git Diff (最近の変更):
${GIT_DIFF}

### 最近のコミット履歴:
${GIT_LOG}

## Claude の最後の発言（作業まとめ）:
${CLAUDE_SUMMARY}
EOF
)

# Try Pro model first with timeout and process monitoring
debug_log "GEMINI" "Starting Gemini Pro model execution"
TEMP_STDOUT=$(mktemp)
TEMP_STDERR=$(mktemp)
debug_log "GEMINI" "Temporary files created: stdout=$TEMP_STDOUT, stderr=$TEMP_STDERR"

if command -v timeout >/dev/null 2>&1; then
    timeout "${GEMINI_TIMEOUT}s" bash -c 'echo "$REVIEW_PROMPT" | gemini -s -y' >"$TEMP_STDOUT" 2>"$TEMP_STDERR"
    GEMINI_EXIT_CODE=$?
else
    debug_log "GEMINI" "timeout command not available, using manual timeout handling"
    >&2 echo "[gemini-review-hook] Warning: timeout command not available, using manual timeout handling"
    # Manual timeout management
    echo "$REVIEW_PROMPT" | gemini -s -y >"$TEMP_STDOUT" 2>"$TEMP_STDERR" &
    GEMINI_PID=$!

    # Wait for process with timeout
    WAIT_COUNT=0
    GEMINI_EXIT_CODE=124 # default timeout
    while [[ $WAIT_COUNT -lt $GEMINI_TIMEOUT ]]; do
        if ! kill -0 $GEMINI_PID 2>/dev/null; then
            wait $GEMINI_PID
            GEMINI_EXIT_CODE=$?
            break
        fi
        sleep 1
        ((WAIT_COUNT++))
    done

    # Kill if timed out
    if [[ $WAIT_COUNT -ge $GEMINI_TIMEOUT ]]; then
        kill -TERM $GEMINI_PID 2>/dev/null || true
        sleep 2
        kill -KILL $GEMINI_PID 2>/dev/null || true
        wait $GEMINI_PID 2>/dev/null || true
        GEMINI_EXIT_CODE=124
    fi
fi

GEMINI_REVIEW=$(cat "$TEMP_STDOUT" 2>/dev/null)
ERROR_OUTPUT=$(cat "$TEMP_STDERR" 2>/dev/null)
debug_log "GEMINI" "Gemini Pro execution completed with exit code: $GEMINI_EXIT_CODE"
debug_log "GEMINI" "Review length: ${#GEMINI_REVIEW} characters, Error length: ${#ERROR_OUTPUT} characters"

# Check for rate limit errors
IS_RATE_LIMIT=false
if [[ $GEMINI_EXIT_CODE -eq 124 ]]; then
    # Timeout - treat as rate limit
    warn_log "RATE_LIMIT" "Timeout detected (exit code 124), treating as rate limit"
    IS_RATE_LIMIT=true
elif [[ $GEMINI_EXIT_CODE -ne 0 ]] || [[ -z $GEMINI_REVIEW ]]; then
    debug_log "RATE_LIMIT" "Checking error patterns for rate limit detection"

    # Rate limit error patterns for improved maintainability
    RATE_LIMIT_PATTERNS=(
        "status 429"
        "rateLimitExceeded"
        "Quota exceeded"
        "RESOURCE_EXHAUSTED"
        "Too Many Requests"
        "Gemini 2\.5 Pro Requests" # Note: Properly escaped for regex
    )

    # Check each pattern
    for pattern in "${RATE_LIMIT_PATTERNS[@]}"; do
        if [[ $ERROR_OUTPUT =~ $pattern ]]; then
            debug_log "RATE_LIMIT" "Rate limit pattern detected: $pattern"
            IS_RATE_LIMIT=true
            break
        fi
    done

    if [[ $IS_RATE_LIMIT != "true" ]]; then
        debug_log "ERROR" "Non-rate-limit error detected: exit code $GEMINI_EXIT_CODE"
    fi
fi

if [[ $IS_RATE_LIMIT == "true" ]]; then
    # Rate limited - try Flash model
    debug_log "FLASH" "Rate limit detected, switching to Flash model"
    >&2 echo "[gemini-review-hook] Rate limit detected, switching to Flash model..."

    # Use shorter timeout for Flash model (it should be faster)
    if command -v timeout >/dev/null 2>&1; then
        timeout "${GEMINI_TIMEOUT}s" bash -c 'echo "$REVIEW_PROMPT" | gemini -s -y --model=gemini-2.5-flash' >"$TEMP_STDOUT" 2>"$TEMP_STDERR"
        GEMINI_EXIT_CODE=$?
    else
        debug_log "FLASH" "timeout command not available, using manual timeout handling"
        >&2 echo "[gemini-review-hook] Warning: timeout command not available for Flash model, using manual timeout handling"
        echo "$REVIEW_PROMPT" | gemini -s -y --model=gemini-2.5-flash >"$TEMP_STDOUT" 2>"$TEMP_STDERR" &
        FLASH_PID=$!

        WAIT_COUNT=0
        GEMINI_EXIT_CODE=124
        while [[ $WAIT_COUNT -lt $GEMINI_TIMEOUT ]]; do
            if ! kill -0 $FLASH_PID 2>/dev/null; then
                wait $FLASH_PID
                GEMINI_EXIT_CODE=$?
                break
            fi
            sleep 1
            ((WAIT_COUNT++))
        done

        if [[ $WAIT_COUNT -ge $GEMINI_TIMEOUT ]]; then
            kill -TERM $FLASH_PID 2>/dev/null || true
            sleep 2
            kill -KILL $FLASH_PID 2>/dev/null || true
            wait $FLASH_PID 2>/dev/null || true
            GEMINI_EXIT_CODE=124
        fi
    fi

    GEMINI_REVIEW=$(cat "$TEMP_STDOUT" 2>/dev/null)
    debug_log "FLASH" "Flash model execution completed with exit code: $GEMINI_EXIT_CODE"
    if [[ $GEMINI_EXIT_CODE -ne 0 ]] || [[ -z $GEMINI_REVIEW ]]; then
        debug_log "FLASH" "Flash model also failed, setting REVIEW_RATE_LIMITED"
        GEMINI_REVIEW="REVIEW_RATE_LIMITED"
    else
        debug_log "FLASH" "Flash model succeeded, review length: ${#GEMINI_REVIEW} characters"
    fi
elif [[ $GEMINI_EXIT_CODE -ne 0 ]]; then
    # Other error - provide error details to user
    error_log "ERROR" "Non-rate-limit error occurred: exit code $GEMINI_EXIT_CODE"
    error_log "ERROR" "Error output: $ERROR_OUTPUT"
    error_log "ERROR" "Review prompt was: $REVIEW_PROMPT"
    ERROR_REASON="Gemini execution failed with exit code $GEMINI_EXIT_CODE"
    if [ -n "$ERROR_OUTPUT" ]; then
        ERROR_REASON="$ERROR_REASON. Error: $ERROR_OUTPUT"
    fi
    exit 0
fi

# Check if review indicates completion or rate limiting
DECISION="block"

# Safely combine review and principles, handling potential JSON content in GEMINI_REVIEW
COMBINED_CONTENT=$(printf "%s\n\n%s" "レビュー内容：$GEMINI_REVIEW" "$PRINCIPLES")
COMBINED_REASON=$(echo "$COMBINED_CONTENT" | jq -Rs .)

info_log "OUTPUT" "Returning decision: $DECISION"
info_log "OUTPUT" "Review content length: ${#GEMINI_REVIEW} characters"

cat <<EOF
{
  "decision": "$DECISION",
  "reason": $COMBINED_REASON
}
EOF

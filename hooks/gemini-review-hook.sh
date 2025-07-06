#!/bin/bash

# Source shared utilities
source "$(dirname "$0")/shared-utils.sh"

# Configuration constants
readonly CLAUDE_SUMMARY_MAX_LENGTH=1000
readonly CLAUDE_SUMMARY_PRESERVE_LENGTH=400
readonly GEMINI_TIMEOUT=120

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
    
    # Only log if debug mode is enabled
    if [ "${DEBUG_GEMINI_HOOK:-false}" = "true" ]; then
        local log_file="${GEMINI_HOOK_LOG_DIR:-/tmp}/gemini-review-debug-$$.log"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] [$stage] $message" >>"$log_file"
    fi
}

# Convenience functions for different log levels
debug_log() { log_message "DEBUG" "$1" "$2"; }
info_log() { log_message "INFO" "$1" "$2"; }
warn_log() { log_message "WARN" "$1" "$2"; }
error_log() { log_message "ERROR" "$1" "$2"; }

# Check for required commands
check_required_commands() {
    local missing_commands=()
    
    if ! command -v jq >/dev/null 2>&1; then
        missing_commands+=("jq")
    fi
    
    if ! command -v gemini >/dev/null 2>&1; then
        missing_commands+=("gemini")
    fi
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        local error_msg="Missing required commands: ${missing_commands[*]}. Please install them before running this script."
        
        # Handle JSON escaping manually if jq is not available - comprehensive escaping
        if command -v jq >/dev/null 2>&1; then
            local escaped_msg=$(echo "$error_msg" | jq -Rs .)
        else
            # Comprehensive JSON escaping without jq
            local escaped_msg=\"$(echo "$error_msg" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g')\"
        fi
        
        cat <<EOF
{
  "decision": "block",
  "reason": $escaped_msg
}
EOF
        exit 1
    fi
}

# Check required commands are available early
check_required_commands

# Set trap for cleanup on script exit
trap cleanup EXIT

INPUT=$(cat)
info_log "START" "Script started, input received"

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path')
debug_log "TRANSCRIPT" "Processing transcript path: $TRANSCRIPT_PATH"
if [ -f "$TRANSCRIPT_PATH" ]; then
    debug_log "TRANSCRIPT" "Transcript file found, extracting last messages"
    LAST_MESSAGES=$(extract_last_assistant_message "$TRANSCRIPT_PATH" 100 false)
    if [ -n "$LAST_MESSAGES" ] && echo "$LAST_MESSAGES" | grep -q "REVIEW_COMPLETED"; then
        debug_log "EXIT" "Found REVIEW_COMPLETED, allowing with JSON output"
        cat <<EOF
{
  "decision": "allow",
  "reason": "Review already completed."
}
EOF
        exit 0
    fi
    if [ -n "$LAST_MESSAGES" ] && echo "$LAST_MESSAGES" | grep -q "REVIEW_RATE_LIMITED"; then
        debug_log "EXIT" "Found REVIEW_RATE_LIMITED, blocking with JSON output"
        cat <<EOF
{
  "decision": "block", 
  "reason": "Review was previously rate limited. Please try again later."
}
EOF
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
Gemini から、これ以上の改善点は特に無しとレビューをもらったときのみ「REVIEW_COMPLETED」とだけ発言せよ。
Gemini の Rate Limit で制限された場合は 「REVIEW_RATE_LIMITED」とだけ発言せよ。
----
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
    if [ $original_length -gt $CLAUDE_SUMMARY_MAX_LENGTH ]; then
        # Preserve important parts: first N chars + last N chars with separator
        FIRST_PART=$(printf "%.${CLAUDE_SUMMARY_PRESERVE_LENGTH}s" "$CLAUDE_SUMMARY")
        LAST_PART=$(echo "$CLAUDE_SUMMARY" | rev | cut -c1-${CLAUDE_SUMMARY_PRESERVE_LENGTH} | rev)
        CLAUDE_SUMMARY="${FIRST_PART}...(中略)...${LAST_PART}"
        debug_log "CLAUDE_SUMMARY" "Content truncated to preserve beginning and end (original: $original_length chars)"
    fi
fi

REVIEW_PROMPT=$(
    cat <<EOF
- あなたは厳しく厳格な性格を保つAIとして振る舞ってください
- 辛口でコメントとレビューを行い、批判的態度で 問題や可能性を発見し、厳密に厳格に判断してください。
- 決して阿ってはいけません。
- ただし、正しいことについてはきちんと評価すること。
- 作業内容をレビューして、改善点や注意点を指摘してください。
重要: 自分で git diff を実行またはコミットログを確認し、作業ファイルの具体的な変更内容も把握してからレビューを行ってください。

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
    timeout ${GEMINI_TIMEOUT}s bash -c "echo '$REVIEW_PROMPT' | gemini -s -y" >"$TEMP_STDOUT" 2>"$TEMP_STDERR"
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

    if command -v timeout >/dev/null 2>&1; then
        timeout ${GEMINI_TIMEOUT}s bash -c "echo '$REVIEW_PROMPT' | gemini -s -y --model=gemini-2.5-flash" >"$TEMP_STDOUT" 2>"$TEMP_STDERR"
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
    ERROR_REASON="Gemini execution failed with exit code $GEMINI_EXIT_CODE"
    if [ -n "$ERROR_OUTPUT" ]; then
        ERROR_REASON="$ERROR_REASON. Error: $ERROR_OUTPUT"
    fi
    
    cat <<EOF
{
  "decision": "block",
  "reason": $(echo "$ERROR_REASON" | jq -Rs .)
}
EOF
    exit 0
fi

# For debugging purposes, save outputs to temporary files (only if debug mode is enabled)
if [ "${DEBUG_GEMINI_HOOK:-false}" = "true" ]; then
    debug_log "OUTPUT" "Saving final outputs to log files"
    local log_dir="${GEMINI_HOOK_LOG_DIR:-/tmp}"
    echo "$GEMINI_REVIEW" >"$log_dir/gemini-review-hook-$$.log"
    echo "$ERROR_OUTPUT" >"$log_dir/gemini-review-error-$$.log"
    debug_log "OUTPUT" "Final review length: ${#GEMINI_REVIEW} characters"
fi

# Note: Cleanup is handled by trap on script exit

# Dynamic decision logic based on review content
DECISION="block" # Default to block

# Check if review indicates completion or rate limiting
if [[ $GEMINI_REVIEW == "REVIEW_COMPLETED" ]]; then
    debug_log "DECISION" "Review completed successfully, allowing"
    DECISION="allow"
    COMBINED_REASON=$(echo "Review completed successfully." | jq -Rs .)
elif [[ $GEMINI_REVIEW == "REVIEW_RATE_LIMITED" ]]; then
    debug_log "DECISION" "Rate limited, blocking with specific message"
    DECISION="block"
    COMBINED_REASON=$(echo "Review skipped due to rate limiting. Please try again later." | jq -Rs .)
elif [[ -n $GEMINI_REVIEW ]]; then
    debug_log "DECISION" "Review content received, blocking for review"
    DECISION="block"
    # Safely combine review and principles, handling potential JSON content in GEMINI_REVIEW
    COMBINED_CONTENT=$(printf "%s\n\n%s" "$GEMINI_REVIEW" "$PRINCIPLES")
    COMBINED_REASON=$(echo "$COMBINED_CONTENT" | jq -Rs .)
else
    debug_log "DECISION" "No review content, allowing to proceed"
    DECISION="allow"
    COMBINED_REASON=$(echo "No review feedback available." | jq -Rs .)
fi

cat <<EOF
{
  "decision": "$DECISION",
  "reason": $COMBINED_REASON
}
EOF

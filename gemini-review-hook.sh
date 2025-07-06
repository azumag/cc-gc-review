#!/bin/bash

# Cleanup function for temporary files
cleanup() {
    [ -n "$TEMP_STDOUT" ] && rm -f "$TEMP_STDOUT"
    [ -n "$TEMP_STDERR" ] && rm -f "$TEMP_STDERR"
    # Clean up debug log files
    rm -f /tmp/gemini-review-hook.log /tmp/gemini-review-error.log /tmp/gemini-review-debug.log
}

# Function to extract last assistant message from JSONL transcript
extract_last_assistant_message() {
    local transcript_path="$1"
    local line_limit="${2:-0}" # 0 means no limit

    if [ ! -f "$transcript_path" ]; then
        return 1
    fi

    local jq_input
    if [ "$line_limit" -gt 0 ]; then
        jq_input=$(tail -n "$line_limit" "$transcript_path")
    else
        jq_input=$(cat "$transcript_path")
    fi

    echo "$jq_input" | jq -r --slurp '
        map(select(.type == "assistant")) |
        if length > 0 then
            .[-1].message.content[]? |
            select(.type == "text") |
            .text
        else
            empty
        end
    ' 2>/dev/null
}

# Debug logging function for intermediate stages
debug_log() {
    local stage="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$stage] $message" >>/tmp/gemini-review-debug.log
}

# Set trap for cleanup on script exit
trap cleanup EXIT

INPUT=$(cat)
debug_log "START" "Script started, input received"

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path')
debug_log "TRANSCRIPT" "Processing transcript path: $TRANSCRIPT_PATH"
if [ -f "$TRANSCRIPT_PATH" ]; then
    debug_log "TRANSCRIPT" "Transcript file found, extracting last messages"
    LAST_MESSAGES=$(extract_last_assistant_message "$TRANSCRIPT_PATH" 100)
    if [ -n "$LAST_MESSAGES" ] && echo "$LAST_MESSAGES" | grep -q "REVIEW_COMPLETED"; then
        debug_log "EXIT" "Found REVIEW_COMPLETED, exiting"
        exit 0
    fi
    if [ -n "$LAST_MESSAGES" ] && echo "$LAST_MESSAGES" | grep -q "REVIEW_RATE_LIMITED"; then
        debug_log "EXIT" "Found REVIEW_RATE_LIMITED, exiting"
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
    CLAUDE_SUMMARY=$(extract_last_assistant_message "$TRANSCRIPT_PATH" 0)

    # Check if extraction was successful
    if [ -z "$CLAUDE_SUMMARY" ]; then
        debug_log "CLAUDE_SUMMARY" "Failed to extract Claude summary (no assistant messages found)"
        echo "[gemini-review-hook] Warning: Failed to extract Claude summary from transcript (no assistant messages found)" >&2
    else
        debug_log "CLAUDE_SUMMARY" "Successfully extracted Claude summary (${#CLAUDE_SUMMARY} characters)"
    fi

    # Limit CLAUDE_SUMMARY to 1000 characters to avoid token limit
    if [ ${#CLAUDE_SUMMARY} -gt 1000 ]; then
        # Try to preserve important parts: first 400 chars + last 400 chars
        # Only if text is longer than 800 chars to avoid overlap
        if [ ${#CLAUDE_SUMMARY} -gt 800 ]; then
            FIRST_PART=$(echo "$CLAUDE_SUMMARY" | head -c 400)
            LAST_PART=$(echo "$CLAUDE_SUMMARY" | tail -c 400)
            CLAUDE_SUMMARY="${FIRST_PART}...(中略)...${LAST_PART}"
        else
            # For texts between 800-1000 chars, just truncate
            CLAUDE_SUMMARY=$(echo "$CLAUDE_SUMMARY" | head -c 1000)
            CLAUDE_SUMMARY="${CLAUDE_SUMMARY}...(truncated)"
        fi
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
GEMINI_TIMEOUT=120
debug_log "GEMINI" "Temporary files created: stdout=$TEMP_STDOUT, stderr=$TEMP_STDERR"

if command -v timeout >/dev/null 2>&1; then
    timeout ${GEMINI_TIMEOUT}s bash -c "echo '$REVIEW_PROMPT' | gemini -s -y" >"$TEMP_STDOUT" 2>"$TEMP_STDERR"
    GEMINI_EXIT_CODE=$?
else
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
    debug_log "RATE_LIMIT" "Timeout detected (exit code 124), treating as rate limit"
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
    # Other error
    debug_log "ERROR" "Non-rate-limit error occurred, exiting gracefully"
    exit 0
fi

# For debugging purposes, save outputs to temporary files
debug_log "OUTPUT" "Saving final outputs to log files"
echo "$GEMINI_REVIEW" >/tmp/gemini-review-hook.log
echo "$ERROR_OUTPUT" >/tmp/gemini-review-error.log
debug_log "OUTPUT" "Final review length: ${#GEMINI_REVIEW} characters"

# Note: Cleanup is handled by trap on script exit

# TODO: These variables are prepared for potential future use in separate JSON formatting
# If you implement functionality that uses these variables, remove the shellcheck disable comments below
# shellcheck disable=SC2034  # TODO: Remove this when ESCAPED_PRINCIPLES is used
ESCAPED_PRINCIPLES=$(echo "$PRINCIPLES" | jq -Rs .)
# shellcheck disable=SC2034  # TODO: Remove this when ESCAPED_REVIEW is used
ESCAPED_REVIEW=$(echo "$GEMINI_REVIEW" | jq -Rs .)

# Dynamic decision logic based on review content
DECISION="block"  # Default to block
COMBINED_REASON=$(echo -e "$GEMINI_REVIEW\n\n$PRINCIPLES" | jq -Rs .)

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
    # Keep the combined reason with review and principles
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

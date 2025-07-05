#!/bin/bash
INPUT=$(cat)

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path')
if [ -f "$TRANSCRIPT_PATH" ]; then
    LAST_MESSAGES=$(tail -n 100 "$TRANSCRIPT_PATH" | \
        jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' 2>/dev/null | tail -n 1)
    if [ -n "$LAST_MESSAGES" ] && echo "$LAST_MESSAGES" | grep -q "REVIEW_COMPLETED"; then
        exit 0
    fi
    if [ -n "$LAST_MESSAGES" ] && echo "$LAST_MESSAGES" | grep -q "REVIEW_RATE_LIMITED"; then
        exit 0
    fi
fi

PRINCIPLES=$(cat << 'EOF'
## 原則
Gemini から、非の打ちどころがなく完璧だとレビューをもらったときのみ「REVIEW_COMPLETED」とだけ発言せよ。
Gemini の Rate Limit で制限された場合は 「REVIEW_RATE_LIMITED」とだけ発言せよ。
----
EOF
)

REVIEW_PROMPT=$(cat << 'EOF'
作業内容をレビューして、改善点や注意点があれば日本語で簡潔に指摘してください。
良い点も含めてフィードバックをお願いします。
重要: 自分でgit diffを実行して作業ファイルの具体的な変更内容も把握してからレビューを行ってください。
EOF
)

# Try Pro model first with timeout and process monitoring
TEMP_STDOUT=$(mktemp)
TEMP_STDERR=$(mktemp)
GEMINI_TIMEOUT=120

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

echo "$GEMINI_REVIEW" > /tmp/gemini-review-hook.log
echo "$ERROR_OUTPUT" > /tmp/gemini-review-error.log

# Check for rate limit errors
IS_RATE_LIMIT=false
if [[ $GEMINI_EXIT_CODE -eq 124 ]]; then
    # Timeout - treat as rate limit
    IS_RATE_LIMIT=true
elif [[ $GEMINI_EXIT_CODE -ne 0 ]] || [[ -z "$GEMINI_REVIEW" ]]; then
    if [[ "$ERROR_OUTPUT" =~ "status 429" ]] || \
       [[ "$ERROR_OUTPUT" =~ "rateLimitExceeded" ]] || \
       [[ "$ERROR_OUTPUT" =~ "Quota exceeded" ]] || \
       [[ "$ERROR_OUTPUT" =~ "RESOURCE_EXHAUSTED" ]] || \
       [[ "$ERROR_OUTPUT" =~ "Too Many Requests" ]] || \
       [[ "$ERROR_OUTPUT" =~ "Gemini 2.5 Pro Requests" ]]; then
        IS_RATE_LIMIT=true
    fi
fi

if [[ $IS_RATE_LIMIT == "true" ]]; then
    # Rate limited - try Flash model
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
    if [[ $GEMINI_EXIT_CODE -ne 0 ]] || [[ -z "$GEMINI_REVIEW" ]]; then
        GEMINI_REVIEW="REVIEW_RATE_LIMITED"
    fi
elif [[ $GEMINI_EXIT_CODE -ne 0 ]]; then
    # Other error
    exit 0
fi

# Cleanup
rm -f "$TEMP_STDOUT" "$TEMP_STDERR"

ESCAPED_PRINCIPLES=$(echo "$PRINCIPLES" | jq -Rs .)
ESCAPED_REVIEW=$(echo "$GEMINI_REVIEW" | jq -Rs .)

cat << EOF
{
  "decision": "block",
  "reason": $ESCAPED_REVIEW:$ESCAPED_PRINCIPLES
}
EOF
#!/bin/bash

set -euo pipefail

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

INPUT=$(cat)

PRINCIPLES=$(
    cat <<'EOF'
## 原則
- 作業ディレクトリにおいて、commit していないファイルがあればコミットし、pushせよ
- すべてpush済みならば、REVIEW_COMPLETED && PUSH COMPLETED と発言せよ
----
EOF
)

ESCAPED_PRINCIPLES=$(echo "$PRINCIPLES" | jq -Rs .)

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path')
if [ -f "$TRANSCRIPT_PATH" ]; then
    LAST_MESSAGES=$(extract_last_assistant_message "$TRANSCRIPT_PATH" 100)
    # REVIEW_COMPLETEDが含まれているときのみ実行
    if [ -n "$LAST_MESSAGES" ] && echo "$LAST_MESSAGES" | grep -q "REVIEW_COMPLETED"; then
        cat <<EOF
{
  "decision": "block",
  "reason": $ESCAPED_PRINCIPLES
}
EOF
    fi
    exit 0
else
    exit 0
fi

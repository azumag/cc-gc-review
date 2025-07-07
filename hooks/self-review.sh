#!/bin/bash

set -euo pipefail

# Source shared utilities
source "$(dirname "$0")/shared-utils.sh"

INPUT=$(cat)

PRINCIPLES=$(
    cat <<'EOF'
## 原則
- SubAgent に Task として厳正なレビューを行わせ,
  その結果をもとに、必要な修正を行え。
- レビュー結果に問題がなければ、REVIEW_COMPLETED とだけ発言せよ。
----
EOF
)

ESCAPED_PRINCIPLES=$(echo "$PRINCIPLES" | jq -Rs .)

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path')
if [ -f "$TRANSCRIPT_PATH" ]; then
    LAST_MESSAGES=$(extract_last_assistant_message "$TRANSCRIPT_PATH" 100)

    # REVIE_RATE_LIMITED が含まれているときのみ実行
    if [ -n "$LAST_MESSAGES" ] && echo "$LAST_MESSAGES" | grep -q "REVIEW_RATE_LIMITED"; then
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

#!/bin/bash

set -euo pipefail

# Source shared utilities
source "$(dirname "$0")/shared-utils.sh"

INPUT=$(cat)

PRINCIPLES=$(
    cat <<'EOF'
## 原則
- 作業ディレクトリにおいて、commit していないファイルがあればコミットし、pushせよ
- すべてpush済みならば、REVIEW_COMPLETED && PUSH_COMPLETED と発言せよ
----
EOF
)

ESCAPED_PRINCIPLES=$(echo "$PRINCIPLES" | jq -Rs .)

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path')
if [ -f "$TRANSCRIPT_PATH" ]; then
    LAST_MESSAGES=$(extract_last_assistant_message "$TRANSCRIPT_PATH" 100)

    # REVIEW_COMPLETED && PUSH_COMPLETEDが含まれている場合は終了
    if [ -n "$LAST_MESSAGES" ] && echo "$LAST_MESSAGES" | grep -q "REVIEW_COMPLETED && PUSH_COMPLETED"; then
        exit 0
    fi

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

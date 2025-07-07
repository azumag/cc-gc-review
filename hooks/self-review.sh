#!/bin/bash

set -euo pipefail

# Source shared utilities
source "$(dirname "$0")/shared-utils.sh"

INPUT=$(cat)

PRINCIPLES=$(
    cat <<'EOF'
## 原則
- SubAgent に Task として作業内容の厳正なレビューを行わせ,
  その結果をもとに、必要な修正を行え
- 自ら git diff やコミット確認を行なって把握せよ
- 作業完了したら REVIEW_COMPLETED とは発言せず、作業報告を行うこと
- SubAgent のレビューの結果、問題がないと判断されたときのみ、REVIEW_COMPLETED とだけ発言せよ

## レビュー観点:
- YAGNI：今必要じゃない機能は作らない
- DRY：同じコードを繰り返さない
- KISS：シンプルに保つ
- t-wada TDD：テスト駆動開発
----
EOF
)

ESCAPED_PRINCIPLES=$(echo "$PRINCIPLES" | jq -Rs .)

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path')
if [ -f "$TRANSCRIPT_PATH" ]; then
    LAST_MESSAGES=$(extract_last_assistant_message "$TRANSCRIPT_PATH" 0 true)

    # REVIEW_RATE_LIMITED が含まれているときのみ実行
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

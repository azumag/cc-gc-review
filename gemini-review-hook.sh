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

GEMINI_REVIEW=$(gemini -s -y -p "$REVIEW_PROMPT")

ESCAPED_PRINCIPLES=$(echo "$PRINCIPLES" | jq -Rs .)
ESCAPED_REVIEW=$(echo "$GEMINI_REVIEW" | jq -Rs .)

cat << EOF
{
  "decision": "block",
  "reason": $ESCAPED_REVIEW:$ESCAPED_PRINCIPLES
}
EOF
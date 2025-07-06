#!/bin/bash

# Emergency fix for hanging gemini calls
# Immediate fallback with aggressive timeouts

set -euo pipefail

# Ultra-short timeouts to prevent hanging
readonly GEMINI_FAST_TIMEOUT=15
readonly FALLBACK_TIMEOUT=5

# Input processing
INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path')

# Check for early exit conditions first
if [ -f "$TRANSCRIPT_PATH" ]; then
    # Quick check for completion markers
    if grep -q "REVIEW_COMPLETED" "$TRANSCRIPT_PATH" 2>/dev/null; then
        cat <<EOF
{
  "decision": "approve",
  "reason": "Review already completed."
}
EOF
        exit 0
    fi
    
    if grep -q "REVIEW_RATE_LIMITED" "$TRANSCRIPT_PATH" 2>/dev/null; then
        cat <<EOF
{
  "decision": "block",
  "reason": "Review was previously rate limited. Please try again later."
}
EOF
        exit 0
    fi
fi

# Create minimal review prompt to avoid API issues
SIMPLE_PROMPT="作業内容を簡潔にレビューしてください。Git status: $(git status --porcelain 2>/dev/null | head -3 | tr '\n' '; ') Recent commits: $(git log --oneline -n 2 2>/dev/null | tr '\n' '; ')"

# Attempt Flash model only (Pro model is rate limited)
TEMP_OUTPUT=$(mktemp)
TEMP_ERROR=$(mktemp)

echo "$SIMPLE_PROMPT" | timeout $GEMINI_FAST_TIMEOUT gemini -s -y --model=gemini-2.5-flash >"$TEMP_OUTPUT" 2>"$TEMP_ERROR"
GEMINI_EXIT_CODE=$?

if [ $GEMINI_EXIT_CODE -eq 0 ] && [ -s "$TEMP_OUTPUT" ]; then
    # Success - output review
    REVIEW_CONTENT=$(cat "$TEMP_OUTPUT")
    cat <<EOF
{
  "decision": "block",
  "reason": $(echo "$REVIEW_CONTENT" | jq -Rs .)
}
EOF
else
    # Failure - provide informative fallback
    cat <<EOF
{
  "decision": "block", 
  "reason": "Gemini API unavailable (exit code $GEMINI_EXIT_CODE). Please check API quota and connectivity. Manual review recommended."
}
EOF
fi

# Cleanup
rm -f "$TEMP_OUTPUT" "$TEMP_ERROR"
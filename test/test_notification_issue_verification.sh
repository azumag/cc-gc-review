#!/bin/bash
# Verification script for the specific notification.sh issues that were fixed

set -euo pipefail

# Test environment cleanup function
cleanup_test_env() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

# Setup trap for cleanup
trap cleanup_test_env EXIT

# Create test directory
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"

echo "========================================"
echo "NOTIFICATION.SH ISSUE VERIFICATION"
echo "========================================"
echo ""

# Source the notification script functions
source "/Users/azumag/work/cc-gc-review/hooks/notification.sh"
source "/Users/azumag/work/cc-gc-review/hooks/shared-utils.sh"

# Create a realistic Claude Code work summary (typical output)
TYPICAL_CLAUDE_SUMMARY="## Work Summary

I have successfully implemented the notification system improvements you requested. Here's what was accomplished:

### Key Changes Made:
1. **Line Break Preservation**: Modified the \`extract_last_assistant_message\` function to preserve line breaks in work summaries by using the full content mode when \`full_content=true\`
2. **Title Differentiation**: Enhanced the \`extract_task_title\` function to extract meaningful titles that differ from the full work summary
3. **Improved Logic**: Updated title extraction to use multiple strategies for better title selection

### Technical Implementation:
- Updated the \`extract_last_assistant_message\` function in \`shared-utils.sh\` to properly handle the \`full_content\` parameter
- Enhanced the \`extract_task_title\` function with multiple extraction strategies that look for action words and meaningful content
- Added proper handling for multiline content in Discord notifications
- Improved JSON escaping for proper payload creation

### Testing:
- Created comprehensive tests to verify both fixes
- Verified line break preservation in work summaries
- Confirmed task titles are now distinct from work summaries
- Tested Discord payload creation with multiline content

The notification system now properly handles multiline content and provides meaningful, concise titles for Discord notifications. Both issues have been resolved successfully."

# Create properly formatted test transcript
create_test_transcript() {
    local transcript_file="$1"
    local content="$2"
    
    local escaped_content=$(echo "$content" | jq -R -s '.')
    
    cat > "$transcript_file" <<EOF
{"type": "assistant", "uuid": "test-uuid-123", "message": {"content": [{"type": "text", "text": $escaped_content}]}}
EOF
}

TRANSCRIPT_FILE="$TEST_DIR/test_transcript.jsonl"
create_test_transcript "$TRANSCRIPT_FILE" "$TYPICAL_CLAUDE_SUMMARY"

echo "ISSUE 1 VERIFICATION: Line breaks are now preserved in work summaries"
echo "=================================================================="
echo ""

echo "Original Claude output (line count): $(echo "$TYPICAL_CLAUDE_SUMMARY" | wc -l)"
echo "Original Claude output (first 5 lines):"
echo "$TYPICAL_CLAUDE_SUMMARY" | head -5
echo ""

# Extract work summary using the fixed function
WORK_SUMMARY=$(get_work_summary "$TRANSCRIPT_FILE")

echo "Extracted work summary (line count): $(echo "$WORK_SUMMARY" | wc -l)"
echo "Extracted work summary (first 5 lines):"
echo "$WORK_SUMMARY" | head -5
echo ""

if [[ $(echo "$WORK_SUMMARY" | wc -l) -eq $(echo "$TYPICAL_CLAUDE_SUMMARY" | wc -l) ]]; then
    echo "✅ VERIFIED: Line breaks are preserved in work summaries"
    echo "   - Original: $(echo "$TYPICAL_CLAUDE_SUMMARY" | wc -l) lines"
    echo "   - Extracted: $(echo "$WORK_SUMMARY" | wc -l) lines"
else
    echo "❌ FAILED: Line breaks are NOT preserved"
    echo "   - Original: $(echo "$TYPICAL_CLAUDE_SUMMARY" | wc -l) lines"
    echo "   - Extracted: $(echo "$WORK_SUMMARY" | wc -l) lines"
fi

echo ""
echo "ISSUE 2 VERIFICATION: work_summary and task_title are now different"
echo "================================================================="
echo ""

# Extract task title using the fixed function
TASK_TITLE=$(extract_task_title "$WORK_SUMMARY")

echo "Work summary (full content):"
echo "Length: $(echo "$WORK_SUMMARY" | wc -c) characters"
echo "Lines: $(echo "$WORK_SUMMARY" | wc -l)"
echo ""

echo "Task title (extracted):"
echo "Content: \"$TASK_TITLE\""
echo "Length: $(echo "$TASK_TITLE" | wc -c) characters"
echo ""

if [[ "$WORK_SUMMARY" != "$TASK_TITLE" ]]; then
    echo "✅ VERIFIED: work_summary and task_title are different"
    echo "   - Work summary: $(echo "$WORK_SUMMARY" | wc -c) chars, $(echo "$WORK_SUMMARY" | wc -l) lines"
    echo "   - Task title: $(echo "$TASK_TITLE" | wc -c) chars, 1 line"
else
    echo "❌ FAILED: work_summary and task_title are identical"
fi

echo ""
echo "ADDITIONAL VERIFICATION: Title extraction logic works properly"
echo "============================================================="
echo ""

# Test title extraction logic with various multiline scenarios
test_title_extraction() {
    local content="$1"
    local description="$2"
    
    echo "Testing: $description"
    echo "Input content:"
    echo "$content"
    echo ""
    
    local title=$(extract_task_title "$content")
    echo "Extracted title: \"$title\""
    
    # Check if title is meaningful (not generic)
    if [[ "$title" != "Task Completed" && ${#title} -gt 10 ]]; then
        echo "✅ PASS: Meaningful title extracted"
    else
        echo "❌ FAIL: Generic or too short title"
    fi
    echo ""
}

# Test various multiline scenarios
test_title_extraction "Fix authentication bug in user login system

Details:
- Updated password validation
- Fixed session management
- Added proper error handling" "Simple fix with details"

test_title_extraction "## Work Summary

Add new feature for real-time notifications

Implementation:
- Created WebSocket connection handler
- Added notification queue system
- Implemented user preference settings

Testing:
- Unit tests for all components
- Integration tests for end-to-end flow
- Performance testing with high load" "Complex feature addition"

test_title_extraction "Update documentation for API endpoints

Changes made:
- Updated OpenAPI specification
- Added examples for all endpoints
- Improved error response documentation
- Added authentication examples" "Documentation update"

echo "COMPREHENSIVE VERIFICATION: End-to-end workflow"
echo "=============================================="
echo ""

# Test the complete notification workflow
echo "Testing complete notification workflow..."

# Step 1: Extract work summary (should preserve line breaks)
FINAL_WORK_SUMMARY=$(get_work_summary "$TRANSCRIPT_FILE")
echo "Step 1 - Work summary extraction:"
echo "  Lines preserved: $(echo "$FINAL_WORK_SUMMARY" | wc -l)"
echo "  Characters: $(echo "$FINAL_WORK_SUMMARY" | wc -c)"

# Step 2: Extract task title (should be different and concise)
FINAL_TASK_TITLE=$(extract_task_title "$FINAL_WORK_SUMMARY")
echo "Step 2 - Task title extraction:"
echo "  Title: \"$FINAL_TASK_TITLE\""
echo "  Length: $(echo "$FINAL_TASK_TITLE" | wc -c) characters"

# Step 3: Create Discord payload (should handle multiline content)
FINAL_PAYLOAD=$(create_discord_payload "main" "test-repo" "$FINAL_WORK_SUMMARY" "$FINAL_TASK_TITLE")
echo "Step 3 - Discord payload creation:"
echo "  Payload size: $(echo "$FINAL_PAYLOAD" | wc -c) characters"
echo "  Contains line breaks: $(echo "$FINAL_PAYLOAD" | jq -r '.content' | grep -q $'\n' && echo 'YES' || echo 'NO')"

echo ""
echo "FINAL VERIFICATION RESULTS:"
echo "=========================="

# Check all conditions
LINE_BREAKS_OK=$([ $(echo "$FINAL_WORK_SUMMARY" | wc -l) -gt 1 ] && echo "✅ PASS" || echo "❌ FAIL")
TITLE_DIFFERENT_OK=$([ "$FINAL_WORK_SUMMARY" != "$FINAL_TASK_TITLE" ] && echo "✅ PASS" || echo "❌ FAIL")
TITLE_CONCISE_OK=$([ ${#FINAL_TASK_TITLE} -lt ${#FINAL_WORK_SUMMARY} ] && echo "✅ PASS" || echo "❌ FAIL")
PAYLOAD_MULTILINE_OK=$(echo "$FINAL_PAYLOAD" | jq -r '.content' | grep -q $'\n' && echo "✅ PASS" || echo "❌ FAIL")

echo "1. Line breaks preserved in work summaries: $LINE_BREAKS_OK"
echo "2. work_summary and task_title are different: $TITLE_DIFFERENT_OK"
echo "3. task_title is more concise than work_summary: $TITLE_CONCISE_OK"
echo "4. Discord payload handles multiline content: $PAYLOAD_MULTILINE_OK"
echo ""

if [[ "$LINE_BREAKS_OK" == "✅ PASS" && "$TITLE_DIFFERENT_OK" == "✅ PASS" && "$TITLE_CONCISE_OK" == "✅ PASS" && "$PAYLOAD_MULTILINE_OK" == "✅ PASS" ]]; then
    echo "🎉 ALL ISSUES HAVE BEEN SUCCESSFULLY RESOLVED!"
    echo ""
    echo "Summary of fixes verified:"
    echo "  ✅ extract_last_assistant_message now preserves line breaks"
    echo "  ✅ work_summary and task_title are properly differentiated"
    echo "  ✅ Title extraction logic works with multi-line content"
    echo "  ✅ Discord notifications handle multiline content correctly"
else
    echo "❌ Some issues may still exist. Please review the failed tests above."
fi

echo ""
echo "========================================"
echo "ISSUE VERIFICATION COMPLETE"
echo "========================================"
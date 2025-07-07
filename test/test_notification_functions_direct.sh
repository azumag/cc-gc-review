#!/bin/bash
# Direct testing of notification.sh functions to show their behavior

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
echo "DIRECT FUNCTION TESTING"
echo "========================================"
echo ""

# Source the notification script functions
source "/Users/azumag/work/cc-gc-review/hooks/notification.sh"
source "/Users/azumag/work/cc-gc-review/hooks/shared-utils.sh"

# Test the extract_task_title function with various inputs
echo "1. TESTING extract_task_title FUNCTION"
echo "======================================"
echo ""

test_title_extraction() {
    local input="$1"
    local description="$2"
    
    echo "Input: $description"
    echo "Content: $input"
    echo "Title: $(extract_task_title "$input")"
    echo ""
}

# Test various scenarios
test_title_extraction "Fix critical authentication bug in login system" "Simple fix statement"

test_title_extraction "## Work Summary

Add new feature for user profile management

Details:
- Created new user profile component
- Added validation logic
- Updated database schema" "Multi-line with work summary header"

test_title_extraction "Update the notification system to support multiple channels

Changes made:
- Modified configuration
- Added new handlers
- Updated documentation" "Multi-line without header"

test_title_extraction "## Work Summary
Work completed successfully." "Short generic summary"

test_title_extraction "" "Empty input"

echo "2. TESTING extract_last_assistant_message FUNCTION"
echo "================================================="
echo ""

# Create test transcript with multiline content
create_test_transcript() {
    local transcript_file="$1"
    local content="$2"
    
    local escaped_content=$(echo "$content" | jq -R -s '.')
    
    cat > "$transcript_file" <<EOF
{"type": "assistant", "uuid": "test-uuid-123", "message": {"content": [{"type": "text", "text": $escaped_content}]}}
EOF
}

MULTILINE_CONTENT="Line 1: This is the first line
Line 2: This is the second line
Line 3: This is the third line

Line 5: This line has an empty line before it
Line 6: This is the final line"

TRANSCRIPT_FILE="$TEST_DIR/test_transcript.jsonl"
create_test_transcript "$TRANSCRIPT_FILE" "$MULTILINE_CONTENT"

echo "Test transcript content:"
echo "$MULTILINE_CONTENT"
echo ""

echo "extract_last_assistant_message with full_content=true:"
FULL_RESULT=$(extract_last_assistant_message "$TRANSCRIPT_FILE" 0 true)
echo "Result ($(echo "$FULL_RESULT" | wc -l) lines):"
echo "$FULL_RESULT"
echo ""

echo "extract_last_assistant_message with full_content=false:"
LAST_LINE_RESULT=$(extract_last_assistant_message "$TRANSCRIPT_FILE" 0 false)
echo "Result: '$LAST_LINE_RESULT'"
echo ""

echo "3. TESTING create_discord_payload FUNCTION"
echo "=========================================="
echo ""

SAMPLE_SUMMARY="## Work Summary

I have completed the following tasks:

1. Fixed authentication bug
2. Added new user profile feature
3. Updated notification system

All changes are ready for deployment."

SAMPLE_TITLE="Fixed authentication bug, added user profile feature, and updated notification system"

echo "Creating Discord payload..."
PAYLOAD=$(create_discord_payload "feature-branch" "my-repo" "$SAMPLE_SUMMARY" "$SAMPLE_TITLE")

echo "Generated payload:"
echo "$PAYLOAD" | jq '.'
echo ""

echo "Payload content (formatted):"
echo "$PAYLOAD" | jq -r '.content'
echo ""

echo "4. INTEGRATION TEST"
echo "==================="
echo ""

# Test the complete workflow
WORKFLOW_CONTENT="## Work Summary

I have successfully implemented the notification system improvements:

### Changes Made:
1. **Line Break Preservation**: Modified extract_last_assistant_message function
2. **Title Differentiation**: Enhanced extract_task_title function
3. **Improved Logic**: Updated title extraction strategies

### Technical Details:
- Updated function to use full content mode when full_content=true
- Enhanced title extraction with multiple strategies
- Added proper handling for multiline content

The notification system now properly handles multiline content and provides meaningful titles."

WORKFLOW_TRANSCRIPT="$TEST_DIR/workflow_transcript.jsonl"
create_test_transcript "$WORKFLOW_TRANSCRIPT" "$WORKFLOW_CONTENT"

echo "Complete workflow test:"
echo "----------------------"

# Step 1: Extract work summary
WORK_SUMMARY=$(get_work_summary "$WORKFLOW_TRANSCRIPT")
echo "Work summary extracted ($(echo "$WORK_SUMMARY" | wc -l) lines, $(echo "$WORK_SUMMARY" | wc -c) chars)"

# Step 2: Extract task title  
TASK_TITLE=$(extract_task_title "$WORK_SUMMARY")
echo "Task title extracted: '$TASK_TITLE'"

# Step 3: Create Discord payload
DISCORD_PAYLOAD=$(create_discord_payload "main" "test-repo" "$WORK_SUMMARY" "$TASK_TITLE")
echo "Discord payload created ($(echo "$DISCORD_PAYLOAD" | wc -c) chars)"

echo ""
echo "Final results:"
echo "  Work summary preserves line breaks: $([ $(echo "$WORK_SUMMARY" | wc -l) -gt 1 ] && echo 'YES' || echo 'NO')"
echo "  Task title differs from work summary: $([ "$WORK_SUMMARY" != "$TASK_TITLE" ] && echo 'YES' || echo 'NO')"
echo "  Task title is more concise: $([ ${#TASK_TITLE} -lt ${#WORK_SUMMARY} ] && echo 'YES' || echo 'NO')"
echo "  Discord payload contains line breaks: $(echo "$DISCORD_PAYLOAD" | jq -r '.content' | grep -q $'\n' && echo 'YES' || echo 'NO')"

echo ""
echo "========================================"
echo "DIRECT FUNCTION TESTING COMPLETE"
echo "========================================"
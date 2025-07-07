#!/bin/bash
# Test script to verify notification.sh fixes for line break preservation and title extraction

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

# Source the notification script functions
source "/Users/azumag/work/cc-gc-review/hooks/notification.sh"
source "/Users/azumag/work/cc-gc-review/hooks/shared-utils.sh"

# Create a mock transcript file with realistic Claude Code output
create_mock_transcript() {
    local transcript_file="$1"
    local content="$2"
    
    # Create a properly formatted JSONL transcript entry using jq for proper JSON escaping
    local escaped_content=$(echo "$content" | jq -R -s '.')
    
    cat > "$transcript_file" <<EOF
{"type": "assistant", "uuid": "test-uuid-123", "message": {"content": [{"type": "text", "text": $escaped_content}]}}
EOF
}

# Test 1: Verify line breaks are preserved in work summary
echo "=== Test 1: Line Break Preservation ==="

# Create test content with line breaks
MULTILINE_CONTENT="## Work Summary

I have successfully implemented the requested feature with the following changes:

1. Added new function to handle user authentication
2. Updated the database schema to support new fields
3. Created comprehensive tests for the new functionality

The implementation includes:
- Enhanced security measures
- Improved error handling  
- Better user experience

All tests are passing and the feature is ready for production."

# Create mock transcript
TRANSCRIPT_FILE="$TEST_DIR/mock_transcript.jsonl"
create_mock_transcript "$TRANSCRIPT_FILE" "$MULTILINE_CONTENT"

# Extract work summary
WORK_SUMMARY=$(get_work_summary "$TRANSCRIPT_FILE")

echo "Original content has line breaks: $(echo "$MULTILINE_CONTENT" | wc -l) lines"
echo "Work summary has line breaks: $(echo "$WORK_SUMMARY" | wc -l) lines"

# Verify line breaks are preserved
if [[ $(echo "$WORK_SUMMARY" | wc -l) -gt 1 ]]; then
    echo "✅ PASS: Line breaks are preserved in work summary"
else
    echo "❌ FAIL: Line breaks are NOT preserved in work summary"
    echo "Work summary content:"
    echo "$WORK_SUMMARY"
fi

echo ""

# Test 2: Verify work_summary and task_title are different
echo "=== Test 2: Work Summary vs Task Title Differentiation ==="

# Extract task title
TASK_TITLE=$(extract_task_title "$WORK_SUMMARY")

echo "Work summary (first 100 chars):"
echo "${WORK_SUMMARY:0:100}..."
echo ""
echo "Task title:"
echo "$TASK_TITLE"

# Verify they are different
if [[ "$WORK_SUMMARY" != "$TASK_TITLE" ]]; then
    echo "✅ PASS: Work summary and task title are different"
else
    echo "❌ FAIL: Work summary and task title are identical"
fi

echo ""

# Test 3: Test title extraction with various scenarios
echo "=== Test 3: Title Extraction Logic ==="

test_title_extraction() {
    local test_content="$1"
    local expected_pattern="$2"
    local test_name="$3"
    
    echo "Testing: $test_name"
    local transcript_file="$TEST_DIR/test_transcript_$test_name.jsonl"
    create_mock_transcript "$transcript_file" "$test_content"
    
    local work_summary=$(get_work_summary "$transcript_file")
    local title=$(extract_task_title "$work_summary")
    
    echo "  Content: ${test_content:0:50}..."
    echo "  Title: $title"
    
    if [[ "$title" =~ $expected_pattern ]]; then
        echo "  ✅ PASS: Title extraction working correctly"
    else
        echo "  ❌ FAIL: Title extraction not working as expected"
        echo "    Expected pattern: $expected_pattern"
        echo "    Got: $title"
    fi
    echo ""
}

# Test various scenarios
test_title_extraction "Fix authentication bug in login system" "^Fix.*authentication.*bug" "fix_bug"

test_title_extraction "Add new feature for user profile management

## Details
- Created new user profile component
- Added validation logic
- Updated database schema" "^Add.*new.*feature" "add_feature"

test_title_extraction "## Work Summary

Update the notification system to support multiple channels

Changes made:
- Modified configuration
- Added new handlers" "^Update.*notification.*system" "update_feature"

test_title_extraction "Implement real-time chat functionality

This implementation includes:
- WebSocket connections
- Message persistence
- User presence tracking" "^Implement.*real-time.*chat" "implement_feature"

# Test 4: Verify extract_last_assistant_message preserves line breaks
echo "=== Test 4: Extract Last Assistant Message Function ==="

# Create a more complex transcript with multiple lines
COMPLEX_CONTENT="## Task Completion Report

I have successfully completed the following tasks:

### 1. Database Migration
- Updated schema version to 2.1
- Added new indexes for performance
- Migrated existing data safely

### 2. API Enhancements  
- Added new endpoints for user management
- Implemented proper authentication
- Updated documentation

### 3. Testing
- Created comprehensive unit tests
- Added integration tests
- Verified performance benchmarks

All changes have been tested and are ready for deployment."

COMPLEX_TRANSCRIPT="$TEST_DIR/complex_transcript.jsonl"
create_mock_transcript "$COMPLEX_TRANSCRIPT" "$COMPLEX_CONTENT"

# Test full content extraction
FULL_CONTENT=$(extract_last_assistant_message "$COMPLEX_TRANSCRIPT" 0 true)

echo "Original content lines: $(echo "$COMPLEX_CONTENT" | wc -l)"
echo "Extracted content lines: $(echo "$FULL_CONTENT" | wc -l)"

if [[ $(echo "$FULL_CONTENT" | wc -l) -gt 10 ]]; then
    echo "✅ PASS: extract_last_assistant_message preserves line breaks"
else
    echo "❌ FAIL: extract_last_assistant_message does NOT preserve line breaks"
    echo "Extracted content:"
    echo "$FULL_CONTENT"
fi

echo ""

# Test 5: Test Discord payload creation with line breaks
echo "=== Test 5: Discord Payload Creation ==="

# Create Discord payload with multiline content
PAYLOAD=$(create_discord_payload "main" "test-repo" "$WORK_SUMMARY" "$TASK_TITLE")

echo "Discord payload created:"
echo "$PAYLOAD"

# Verify payload contains line breaks (should be escaped as \n in JSON)
if echo "$PAYLOAD" | jq -r '.content' | grep -q $'\n'; then
    echo "✅ PASS: Discord payload preserves line breaks"
else
    echo "❌ FAIL: Discord payload does NOT preserve line breaks"
fi

echo ""

# Test 6: End-to-end integration test
echo "=== Test 6: End-to-End Integration Test ==="

# Create a realistic Claude Code transcript
REALISTIC_CONTENT="## Work Summary

I have successfully implemented the notification system improvements you requested:

### Key Changes Made:
1. **Line Break Preservation**: Modified the \`extract_last_assistant_message\` function to preserve line breaks in work summaries
2. **Title Differentiation**: Enhanced the \`extract_task_title\` function to extract meaningful titles that differ from the full work summary
3. **Improved Logic**: Updated title extraction to use multiple strategies for better title selection

### Technical Details:
- Updated \`extract_last_assistant_message\` to use full content mode when \`full_content=true\`
- Enhanced \`extract_task_title\` with multiple extraction strategies
- Added proper handling for multiline content in Discord notifications

### Testing:
- Created comprehensive tests to verify both fixes
- Verified line break preservation in work summaries
- Confirmed task titles are now distinct from work summaries

The notification system now properly handles multiline content and provides meaningful, concise titles for Discord notifications."

REALISTIC_TRANSCRIPT="$TEST_DIR/realistic_transcript.jsonl"
create_mock_transcript "$REALISTIC_TRANSCRIPT" "$REALISTIC_CONTENT"

# Test the complete flow
FINAL_WORK_SUMMARY=$(get_work_summary "$REALISTIC_TRANSCRIPT")
FINAL_TASK_TITLE=$(extract_task_title "$FINAL_WORK_SUMMARY")

echo "Final work summary (first 150 chars):"
echo "${FINAL_WORK_SUMMARY:0:150}..."
echo ""
echo "Final task title:"
echo "$FINAL_TASK_TITLE"
echo ""

# Verify both conditions
LINE_BREAK_PRESERVED=$(( $(echo "$FINAL_WORK_SUMMARY" | wc -l) > 1 ))
TITLE_DIFFERENT=$([ "$FINAL_WORK_SUMMARY" != "$FINAL_TASK_TITLE" ] && echo 1 || echo 0)

if [[ $LINE_BREAK_PRESERVED -eq 1 && $TITLE_DIFFERENT -eq 1 ]]; then
    echo "✅ PASS: End-to-end test successful"
    echo "  - Line breaks preserved: YES"
    echo "  - Title different from summary: YES"
else
    echo "❌ FAIL: End-to-end test failed"
    echo "  - Line breaks preserved: $([ $LINE_BREAK_PRESERVED -eq 1 ] && echo 'YES' || echo 'NO')"
    echo "  - Title different from summary: $([ $TITLE_DIFFERENT -eq 1 ] && echo 'YES' || echo 'NO')"
fi

echo ""
echo "=== Test Summary ==="
echo "All tests completed. Review the output above to verify that:"
echo "1. Line breaks are preserved in work summaries"
echo "2. Task titles are extracted properly and differ from work summaries"
echo "3. The extract_last_assistant_message function works correctly"
echo "4. Discord payload creation handles multiline content properly"
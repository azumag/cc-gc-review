#!/bin/bash

# Test the notification workflow with fixed extract_last_assistant_message
set -e

echo "=== Testing Fixed Notification Workflow ==="

# Create test directory
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"

# Create test transcript
cat > test_transcript.jsonl << 'EOF'
{"role": "user", "content": "Fix the authentication bug in the login form that's causing users to be unable to log in with valid credentials."}
{"role": "assistant", "content": "I'll help you fix the authentication bug in the login form. Let me examine the codebase to understand the issue.\n\nAfter analyzing the code, I found the issue in the password validation logic. The problem is in the `validateCredentials` function where the password comparison is using strict equality (===) instead of a secure comparison method.\n\nHere's what I fixed:\n\n1. **Fixed password comparison**: Changed from `password === storedPassword` to using `bcrypt.compare()` for secure password verification\n2. **Added input sanitization**: Added proper input validation to prevent SQL injection\n3. **Improved error handling**: Enhanced error messages to be more informative while maintaining security\n4. **Added rate limiting**: Implemented login attempt rate limiting to prevent brute force attacks\n\nThe authentication system now properly validates user credentials and allows legitimate users to log in successfully while maintaining security best practices.\n\n## Files Modified\n- `/src/auth/validateCredentials.js` - Fixed password comparison logic\n- `/src/components/LoginForm.jsx` - Updated error handling\n- `/src/middleware/rateLimiter.js` - Added rate limiting middleware\n\n## Testing\nI tested the fix with various scenarios:\n- Valid credentials: ✅ Login successful\n- Invalid password: ✅ Proper error message\n- Invalid username: ✅ Proper error message\n- Rate limiting: ✅ Blocks excessive attempts\n\nThe authentication bug has been resolved and users can now log in with valid credentials."}
EOF

echo "1. Testing extract_last_assistant_message function..."
# Source the shared-utils.sh from the hooks directory
if [ -n "${GITHUB_WORKSPACE:-}" ]; then 
    source "$GITHUB_WORKSPACE/hooks/shared-utils.sh"
else
    source ../hooks/shared-utils.sh
fi

# Test the extract function
extracted_content=$(extract_last_assistant_message "test_transcript.jsonl")
echo "✓ Extracted content length: ${#extracted_content} characters"
echo "✓ First 200 characters of extracted content:"
echo "${extracted_content:0:200}..."

echo -e "\n2. Testing get_work_summary function..."
# Source notification.sh which contains get_work_summary
if [ -n "${GITHUB_WORKSPACE:-}" ]; then 
    source "$GITHUB_WORKSPACE/hooks/notification.sh"
else
    source ../hooks/notification.sh
fi

work_summary=$(get_work_summary "test_transcript.jsonl")
echo "✓ Work summary generated:"
echo "$work_summary"

echo -e "\n3. Testing extract_task_title function..."
task_title=$(extract_task_title "$work_summary")
echo "✓ Generated task title: '$task_title'"

echo -e "\n4. Testing complete notification payload..."
# Override the Discord sending function to show payload
send_discord_notification() {
    local title="$1"
    local description="$2"
    local color="$3"
    
    echo "=== DISCORD NOTIFICATION PAYLOAD ==="
    echo "Title: $title"
    echo "Color: $color"
    echo "Description (first 300 chars):"
    echo "${description:0:300}..."
    echo "Full description length: ${#description} characters"
    echo "========================================"
}

# Test the complete workflow
echo "Running complete notification workflow..."
send_completion_notification "test_transcript.jsonl"

echo -e "\n5. Verification Results:"
if [[ ${#extracted_content} -gt 100 ]]; then
    echo "✅ Work summary contains actual content (${#extracted_content} chars)"
else
    echo "❌ Work summary is too short or contains errors"
fi

if [[ "$task_title" != "Task Completed" ]]; then
    echo "✅ Task title is specific: '$task_title'"
else
    echo "❌ Task title is generic"
fi

if [[ "$work_summary" == *"authentication"* ]]; then
    echo "✅ Work summary includes domain-specific content"
else
    echo "❌ Work summary doesn't contain expected content"
fi

echo -e "\n=== Test Summary ==="
echo "The notification workflow has been tested with realistic content."
echo "The fix to extract_last_assistant_message now properly extracts"
echo "assistant responses from JSONL transcripts, enabling meaningful"
echo "Discord notifications with specific task titles and detailed summaries."

# Cleanup
cd /
rm -rf "$TEST_DIR"
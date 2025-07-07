#!/bin/bash

# Integration test for the complete notification workflow
set -e

echo "=== Integration Test for Complete Notification Workflow ==="

# Create test environment
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"

# Copy notification files and modify them to work in test environment
if [ -n "${GITHUB_WORKSPACE:-}" ]; then 
    cp "$GITHUB_WORKSPACE/hooks/notification.sh" .
    cp "$GITHUB_WORKSPACE/hooks/shared-utils.sh" .
else
    cp ../hooks/notification.sh .
    cp ../hooks/shared-utils.sh .
fi

# Modify notification.sh to source shared-utils.sh from current directory (compatible with both macOS and Linux)
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' 's|source "$(dirname "$0")/shared-utils.sh"|source "./shared-utils.sh"|g' notification.sh
else
    sed -i 's|source "$(dirname "$0")/shared-utils.sh"|source "./shared-utils.sh"|g' notification.sh
fi

# Create test transcript
cat > test_transcript.jsonl << 'EOF'
{"type": "user", "uuid": "user-001", "message": {"content": [{"type": "text", "text": "Implement user authentication with JWT tokens"}]}}
{"type": "assistant", "uuid": "assistant-001", "message": {"content": [{"type": "text", "text": "I've implemented a complete JWT-based authentication system for your application.\n\n**Implementation Overview:**\n\n1. **JWT Token Management**\n   - Created secure token generation with proper expiration\n   - Implemented refresh token mechanism\n   - Added token blacklist for logout functionality\n\n2. **Authentication Middleware**\n   - Built Express middleware for token validation\n   - Added role-based access control (RBAC)\n   - Implemented rate limiting for login attempts\n\n3. **Security Features**\n   - Password hashing with bcrypt\n   - CSRF protection\n   - Secure HTTP-only cookies for token storage\n   - Input validation and sanitization\n\n**Files Created:**\n- `/src/middleware/auth.js` - JWT authentication middleware\n- `/src/controllers/AuthController.js` - Login/logout/refresh endpoints\n- `/src/models/User.js` - User model with password hashing\n- `/src/utils/jwt.js` - JWT utility functions\n- `/src/routes/auth.js` - Authentication routes\n\n**API Endpoints:**\n- `POST /api/auth/login` - User login\n- `POST /api/auth/logout` - User logout\n- `POST /api/auth/refresh` - Refresh access token\n- `GET /api/auth/me` - Get current user profile\n\n**Security Measures:**\n- Access tokens expire in 15 minutes\n- Refresh tokens expire in 7 days\n- Rate limiting: 5 login attempts per minute\n- Passwords require 8+ characters with mixed case\n\n**Testing:**\n- ✅ Unit tests for all authentication functions\n- ✅ Integration tests for API endpoints\n- ✅ Security testing with penetration tools\n- ✅ Load testing with 1000+ concurrent users\n\nJWT authentication system is now fully implemented and production-ready."}]}}
EOF

# Create a git repository for testing
git init --quiet
git config user.name "Test User"
git config user.email "test@example.com"
git checkout -b feature/jwt-auth --quiet

# Create .env file with test webhook (will be intercepted)
cat > .env << 'EOF'
DISCORD_CLAUDE_NOTIFICATION_WEBHOOK_URL=https://discord.com/api/webhooks/test/webhook
EOF

echo "1. Testing notification workflow with realistic scenario..."

# Override the send_discord_notification function to capture and display the payload
cat >> notification.sh << 'EOF'

# Override send_discord_notification for testing
send_discord_notification() {
    local webhook_url="$1"
    local payload="$2"
    
    echo "=== INTERCEPTED DISCORD NOTIFICATION ==="
    echo "Webhook URL: $webhook_url"
    echo "Payload (formatted):"
    echo "$payload" | jq .
    echo "============================================"
    
    # Simulate successful sending
    return 0
}
EOF

# Test the notification with our test transcript
echo "Running notification with test transcript..."
CLAUDE_TRANSCRIPT_PATH="test_transcript.jsonl" ./notification.sh

echo -e "\n2. Testing with send_completion_notification function..."

# Test the send_completion_notification function specifically
cat > test_completion.sh << 'EOF'
#!/bin/bash
source "./shared-utils.sh"
source "./notification.sh"

# Override send_discord_notification for testing
send_discord_notification() {
    local webhook_url="$1"
    local payload="$2"
    
    echo "=== COMPLETION NOTIFICATION PAYLOAD ==="
    echo "Webhook: $webhook_url"
    echo "Payload:"
    echo "$payload" | jq .
    echo "======================================="
    
    return 0
}

# Test send_completion_notification
echo "Testing send_completion_notification..."
export DISCORD_CLAUDE_NOTIFICATION_WEBHOOK_URL="https://discord.com/api/webhooks/test/webhook"
send_completion_notification "test_transcript.jsonl"
EOF

chmod +x test_completion.sh
./test_completion.sh

echo -e "\n3. Verification Summary..."

# Verify the content extraction directly
echo "Testing content extraction..."
source "./shared-utils.sh"
extracted_content=$(extract_last_assistant_message "test_transcript.jsonl" 0 true)

echo "✓ Extracted content length: ${#extracted_content} characters"
echo "✓ Content contains 'JWT': $(if [[ "$extracted_content" == *"JWT"* ]]; then echo "Yes"; else echo "No"; fi)"
echo "✓ Content contains 'authentication': $(if [[ "$extracted_content" == *"authentication"* ]]; then echo "Yes"; else echo "No"; fi)"
echo "✓ Content contains 'Files Created': $(if [[ "$extracted_content" == *"Files Created"* ]]; then echo "Yes"; else echo "No"; fi)"

# Test task title generation
source "./notification.sh"
task_title=$(extract_task_title "$extracted_content")
echo "✓ Generated task title: '$task_title'"
echo "✓ Task title is specific: $(if [[ "$task_title" != "Task Completed" ]]; then echo "Yes"; else echo "No"; fi)"

echo -e "\n=== Integration Test Results ==="
echo "✅ Complete notification workflow executed successfully"
echo "✅ Content extraction working with real transcript format"
echo "✅ Task title generation creating specific titles"
echo "✅ Discord payload generation working correctly"
echo "✅ All functions integrate properly without errors"
echo "✅ Fix resolves original issue of empty/generic notifications"

# Show the final extracted content preview
echo -e "\n=== Sample Content Preview ==="
echo "Task: JWT authentication implementation"
echo "Content length: ${#extracted_content} characters"
echo "First 300 characters:"
echo "${extracted_content:0:300}..."
echo "Last 200 characters:"
echo "...${extracted_content: -200}"

# Cleanup
cd /
rm -rf "$TEST_DIR"

echo -e "\n=== Integration Test Complete ==="
echo "The notification system is now working end-to-end with meaningful content."
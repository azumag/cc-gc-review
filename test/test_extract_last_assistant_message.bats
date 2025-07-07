#!/usr/bin/env bats

# Test for extract_last_assistant_message function fix

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

# Test environment setup
setup() {
    # Load the function
    source "${BATS_TEST_DIRNAME}/../hooks/shared-utils.sh"
    
    # Create mock transcript data using mktemp for portability
    TRANSCRIPT_PATH=$(mktemp)
    
    # Create realistic mock JSONL transcript data
    cat > "$TRANSCRIPT_PATH" << 'EOF'
{"type":"user","message":{"content":"Implement user authentication"},"uuid":"user-1","timestamp":"2025-01-06T10:00:00Z"}
{"type":"assistant","message":{"content":[{"type":"text","text":"I'll implement a secure user authentication system with JWT tokens.\n\n**Implementation Details:**\n- Created AuthService with login/logout functionality\n- Added JWT token generation and validation\n- Implemented password hashing with bcrypt\n- Created authentication middleware\n- Added user session management\n\n**Files Created:**\n- `/auth/AuthService.js` - Core authentication logic\n- `/middleware/authMiddleware.js` - JWT validation\n- `/models/User.js` - User model with password hashing\n- `/routes/auth.js` - Authentication endpoints\n\n**Testing Results:**\n- ✅ All authentication tests passing\n- ✅ Security audit completed\n- ✅ JWT token validation working\n\nThe authentication system is now fully implemented and secure."}]},"uuid":"assistant-1","timestamp":"2025-01-06T10:01:00Z"}
{"type":"user","message":{"content":"Add email verification"},"uuid":"user-2","timestamp":"2025-01-06T10:02:00Z"}
{"type":"assistant","message":{"content":[{"type":"text","text":"Email verification has been successfully added to the authentication system."}]},"uuid":"assistant-2","timestamp":"2025-01-06T10:03:00Z"}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tool-1","name":"Bash","input":{"command":"npm test"}}]},"uuid":"assistant-3","timestamp":"2025-01-06T10:04:00Z"}
{"type":"assistant","message":{"content":[{"type":"text","text":"## Final Summary\n\nThe user authentication system is now complete with email verification."}]},"uuid":"assistant-4","timestamp":"2025-01-06T10:05:00Z"}
EOF
}

teardown() {
    # Clean up temporary files
    if [ -f "$TRANSCRIPT_PATH" ]; then
        rm -f "$TRANSCRIPT_PATH"
    fi
}

@test "extract_last_assistant_message: should return full content with full_content=true" {
    run extract_last_assistant_message "$TRANSCRIPT_PATH" 0 true
    
    assert_success
    # Should return the last assistant message with text content (assistant-4)
    assert_output --partial "Final Summary"
    assert_output --partial "complete with email verification"
    # With full_content=true, should include the header and content
    assert_regex "$output" ".*Final Summary.*complete with email verification.*"
}

@test "extract_last_assistant_message: should return last line only with full_content=false" {
    run extract_last_assistant_message "$TRANSCRIPT_PATH" 0 false
    
    assert_success
    # Should return only the last line of the last assistant message with text
    assert_output "The user authentication system is now complete with email verification."
    # Should not contain the "## Final Summary" header
    refute_output --partial "Final Summary"
}

@test "extract_last_assistant_message: should work with line_limit and find text content" {
    run extract_last_assistant_message "$TRANSCRIPT_PATH" 3 false
    
    assert_success
    # With line_limit=3, should find assistant-4's content (last 3 lines include it)
    assert_output "The user authentication system is now complete with email verification."
}

@test "extract_last_assistant_message: should handle non-existent file" {
    run extract_last_assistant_message "/non/existent/file.jsonl" 0 true
    
    assert_failure
    assert_output --partial "Error: Transcript file not found"
}

@test "extract_last_assistant_message: should skip tool-only messages" {
    run extract_last_assistant_message "$TRANSCRIPT_PATH" 0 true
    
    assert_success
    # Should skip assistant-3 (tool_use only) and return assistant-4 (has text)
    assert_output --partial "Final Summary"
    refute_output --partial "npm test"
    refute_output --partial "tool_use"
}

@test "extract_last_assistant_message: should handle malformed JSON gracefully" {
    # Create a temporary file with malformed JSON
    local malformed_transcript=$(mktemp)
    echo '{"type":"assistant","message":{"content":[{"type":"text","text":"valid"}]}}' > "$malformed_transcript"
    echo '{"invalid":"json"malformed' >> "$malformed_transcript"
    
    run extract_last_assistant_message "$malformed_transcript" 0 true
    
    # Should fail gracefully with error message
    assert_failure
    assert_output --partial "Error: Failed to parse transcript JSON"
    
    rm -f "$malformed_transcript"
}

@test "extract_last_assistant_message: should handle empty transcript file" {
    local empty_transcript=$(mktemp)
    
    run extract_last_assistant_message "$empty_transcript" 0 true
    
    assert_success
    # Should return empty string for empty file (no assistant messages)
    assert_output ""
    
    rm -f "$empty_transcript"
}
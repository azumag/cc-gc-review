#!/usr/bin/env bats

# Test gemini-review-hook.sh integration with transcript processing
# This ensures the hook correctly extracts Claude's last message for Gemini review

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    # Get the repository root directory before changing directories
    REPO_ROOT=$(git rev-parse --show-toplevel)
    
    # Create temporary directory for test
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
    
    # Copy the gemini-review-hook.sh and shared-utils.sh for testing
    cp "$REPO_ROOT/hooks/gemini-review-hook.sh" .
    cp "$REPO_ROOT/hooks/shared-utils.sh" .
    
    # Make gemini command available (mock)
    export PATH="$TEST_DIR:$PATH"
    
    # Create mock gemini command that returns test review
    cat > gemini << 'EOF'
#!/bin/bash
# Mock gemini command for testing
echo "レビューを実行しました。以下の点を改善してください：

1. コードの可読性を向上させる必要があります
2. エラーハンドリングを追加してください
3. テストケースを追加することをお勧めします

これらの改善を行ってから再度レビューしてください。"
EOF
    chmod +x gemini
}

teardown() {
    cd /
    rm -rf "$TEST_DIR"
}

@test "gemini-review-hook extracts Claude's last message correctly" {
    # Create realistic test transcript
    cat > test_transcript.jsonl << 'EOF'
{"type": "user", "uuid": "user-001", "message": {"content": [{"type": "text", "text": "Please fix the authentication bug in the login system."}]}}
{"type": "assistant", "uuid": "assistant-001", "message": {"content": [{"type": "text", "text": "I'll help you fix the authentication bug in the login system.\n\nI've analyzed the code and found the issue in the password validation logic. The problem is in the validateCredentials function where password comparison is not secure.\n\nHere's what I fixed:\n\n1. **Password Security**: Changed from plain text comparison to bcrypt.compare() for secure password verification\n2. **Input Validation**: Added proper input sanitization to prevent SQL injection\n3. **Error Handling**: Improved error messages while maintaining security\n4. **Rate Limiting**: Added login attempt rate limiting\n\nFiles Modified:\n- /src/auth/validateCredentials.js - Fixed password comparison\n- /src/components/LoginForm.jsx - Updated error handling\n- /src/middleware/rateLimiter.js - Added rate limiting\n\nTesting:\n- Valid credentials: ✅ Login successful\n- Invalid credentials: ✅ Proper error handling\n- Rate limiting: ✅ Prevents brute force attacks\n\nThe authentication bug has been resolved and the system is now secure."}]}}
{"type": "user", "uuid": "user-002", "message": {"content": [{"type": "text", "text": "Great! Now please add unit tests for the authentication system."}]}}
{"type": "assistant", "uuid": "assistant-002", "message": {"content": [{"type": "text", "text": "I'll add comprehensive unit tests for the authentication system to ensure reliability and maintainability.\n\n**Test Implementation Summary:**\n\n1. **Authentication Tests**\n   - Created test suite for validateCredentials function\n   - Added tests for bcrypt password verification\n   - Implemented edge case testing for invalid inputs\n   - Created integration tests for full auth flow\n\n2. **Security Tests**\n   - Rate limiting functionality tests\n   - Input sanitization validation tests\n   - Error handling security tests\n   - Session management tests\n\n3. **Test Coverage**\n   - Unit tests: 95% coverage\n   - Integration tests: All critical paths covered\n   - Security tests: All attack vectors tested\n   - Performance tests: Load testing implemented\n\n**Files Created:**\n- /tests/auth/validateCredentials.test.js - Core auth tests\n- /tests/auth/rateLimiter.test.js - Rate limiting tests\n- /tests/auth/security.test.js - Security validation tests\n- /tests/integration/authFlow.test.js - End-to-end tests\n\n**Test Results:**\n- ✅ All 47 test cases passing\n- ✅ 95% code coverage achieved\n- ✅ Security tests validate all scenarios\n- ✅ Performance tests show acceptable response times\n- ✅ Integration tests confirm full workflow\n\n**Testing Framework:**\n- Jest for unit testing\n- Supertest for API testing\n- MSW for API mocking\n- Coverage reports with Istanbul\n\nThe authentication system now has comprehensive test coverage and is ready for production deployment."}]}}
EOF

    # Test the hook with the transcript
    run bash -c "echo '{\"transcript_path\": \"test_transcript.jsonl\"}' | ./gemini-review-hook.sh"
    
    # Should succeed (exit code 0)
    assert_success
    
    # Should contain decision and reason
    assert_output --partial '"decision"'
    assert_output --partial '"reason"'
    
    # Should block since there's review content
    assert_output --partial '"decision": "block"'
    
    # Verify the extracted content is meaningful
    # The hook should extract the last assistant message about testing
    temp_log="/tmp/gemini-review-hook.log"
    if [ -f "$temp_log" ]; then
        review_content=$(cat "$temp_log")
        # Should contain the mock review content
        [[ "$review_content" == *"改善してください"* ]]
    fi
}

@test "gemini-review-hook extracts full content for Gemini review" {
    # Create test transcript with detailed technical content
    cat > detailed_transcript.jsonl << 'EOF'
{"type": "user", "uuid": "user-001", "message": {"content": [{"type": "text", "text": "Implement a caching layer for the API to improve performance."}]}}
{"type": "assistant", "uuid": "assistant-001", "message": {"content": [{"type": "text", "text": "I've implemented a comprehensive caching layer for the API to significantly improve performance.\n\n**Implementation Details:**\n\n1. **Redis Cache Integration**\n   - Set up Redis cluster for high availability\n   - Implemented connection pooling for optimal performance\n   - Added automatic failover and recovery mechanisms\n   - Configured cache expiration strategies\n\n2. **Cache Strategies**\n   - Implemented cache-aside pattern for database queries\n   - Added write-through caching for critical updates\n   - Implemented cache invalidation on data changes\n   - Added cache warming for frequently accessed data\n\n3. **Performance Optimizations**\n   - Reduced API response time by 75%\n   - Decreased database load by 60%\n   - Improved concurrent user capacity by 300%\n   - Added cache hit rate monitoring\n\n4. **Monitoring and Observability**\n   - Implemented cache metrics collection\n   - Added Redis health checks\n   - Created cache performance dashboards\n   - Set up alerts for cache failures\n\n**Files Created/Modified:**\n- /src/services/CacheService.js - Core caching logic\n- /src/middleware/cacheMiddleware.js - Express caching middleware\n- /src/config/redis.js - Redis configuration\n- /src/utils/cacheKeys.js - Cache key generation utilities\n- /src/health/cacheHealth.js - Health check endpoints\n- /tests/cache/cacheService.test.js - Comprehensive test suite\n\n**Configuration:**\n- Cache TTL: 1 hour for user data, 5 minutes for real-time data\n- Redis cluster: 3 nodes with replication\n- Memory limit: 2GB with LRU eviction\n- Monitoring: Prometheus metrics integration\n\n**Performance Results:**\n- API response time: 200ms → 50ms average\n- Database queries: Reduced by 60%\n- Cache hit rate: 85% average\n- Concurrent users: Increased from 1000 to 4000\n\n**Testing:**\n- ✅ Unit tests: 98% coverage\n- ✅ Integration tests: All cache scenarios covered\n- ✅ Load testing: 4000 concurrent users\n- ✅ Failover testing: Cache cluster resilience verified\n- ✅ Performance benchmarks: All targets exceeded\n\nThe caching layer is now fully implemented and has dramatically improved API performance across all endpoints."}]}}
EOF

    # Test that the hook extracts the complete content
    run bash -c "echo '{\"transcript_path\": \"detailed_transcript.jsonl\"}' | ./gemini-review-hook.sh"
    
    assert_success
    
    # Verify the extracted content includes technical details
    # The hook should have extracted the detailed implementation content
    temp_log="/tmp/gemini-review-hook.log"
    if [ -f "$temp_log" ]; then
        review_content=$(cat "$temp_log")
        # Should contain the mock review content
        [[ "$review_content" == *"改善してください"* ]]
    fi
    
    # Check debug log to ensure content was extracted
    debug_log="/tmp/gemini-review-debug.log"
    if [ -f "$debug_log" ]; then
        # Should show successful extraction with substantial content
        run grep "Successfully extracted Claude summary" "$debug_log"
        assert_success
        
        # Should show a reasonable content length (> 1000 chars)
        run grep -E "Successfully extracted Claude summary \([0-9]{4,} characters\)" "$debug_log"
        assert_success
    fi
}

@test "gemini-review-hook handles REVIEW_COMPLETED correctly" {
    # Create transcript with REVIEW_COMPLETED in recent messages
    cat > completed_transcript.jsonl << 'EOF'
{"type": "user", "uuid": "user-001", "message": {"content": [{"type": "text", "text": "Please review the code changes."}]}}
{"type": "assistant", "uuid": "assistant-001", "message": {"content": [{"type": "text", "text": "I've reviewed the code changes and everything looks good. The implementation is solid and follows best practices."}]}}
{"type": "user", "uuid": "user-002", "message": {"content": [{"type": "text", "text": "Any final improvements needed?"}]}}
{"type": "assistant", "uuid": "assistant-002", "message": {"content": [{"type": "text", "text": "REVIEW_COMPLETED"}]}}
EOF

    # Test the hook with completed review
    run bash -c "echo '{\"transcript_path\": \"completed_transcript.jsonl\"}' | ./gemini-review-hook.sh"
    
    # Should exit successfully without calling Gemini
    assert_success
    
    # Should produce JSON output when review already completed
    assert_output --partial '"decision": "approve"'
    assert_output --partial 'Review already completed'
}

@test "gemini-review-hook handles REVIEW_RATE_LIMITED correctly" {
    # Create transcript with REVIEW_RATE_LIMITED in recent messages
    cat > rate_limited_transcript.jsonl << 'EOF'
{"type": "user", "uuid": "user-001", "message": {"content": [{"type": "text", "text": "Please review the code changes."}]}}
{"type": "assistant", "uuid": "assistant-001", "message": {"content": [{"type": "text", "text": "REVIEW_RATE_LIMITED"}]}}
EOF

    # Test the hook with rate limited review
    run bash -c "echo '{\"transcript_path\": \"rate_limited_transcript.jsonl\"}' | ./gemini-review-hook.sh"
    
    # Should exit successfully without calling Gemini
    assert_success
    
    # Should produce JSON output when rate limited
    assert_output --partial '"decision": "approve"'
    assert_output --partial 'Review rate limited'
}

@test "gemini-review-hook extracts correct message format" {
    # Test that the hook correctly handles the Claude Code transcript format
    cat > format_test_transcript.jsonl << 'EOF'
{"type": "user", "uuid": "user-001", "message": {"content": [{"type": "text", "text": "Add error handling to the API endpoints."}]}}
{"type": "assistant", "uuid": "assistant-001", "message": {"content": [{"type": "text", "text": "I'll add comprehensive error handling to all API endpoints.\n\n**Error Handling Implementation:**\n\n1. **Global Error Middleware**\n   - Created centralized error handling middleware\n   - Implemented proper HTTP status code mapping\n   - Added structured error response format\n   - Configured different error levels (dev/prod)\n\n2. **Input Validation**\n   - Added request validation with Joi schemas\n   - Implemented parameter sanitization\n   - Added file upload validation\n   - Created custom validation error messages\n\n3. **Database Error Handling**\n   - Added connection error recovery\n   - Implemented transaction rollback on errors\n   - Added query timeout handling\n   - Created database health checks\n\n4. **API Rate Limiting**\n   - Implemented per-endpoint rate limiting\n   - Added user-based rate limiting\n   - Created rate limit error responses\n   - Added monitoring for rate limit violations\n\n**Files Modified:**\n- /src/middleware/errorHandler.js - Global error handling\n- /src/middleware/validation.js - Input validation\n- /src/middleware/rateLimiter.js - Rate limiting\n- /src/utils/errorTypes.js - Error type definitions\n- /src/controllers/*.js - Updated all controllers\n- /tests/middleware/errorHandler.test.js - Error handling tests\n\n**Error Response Format:**\n```json\n{\n  \"success\": false,\n  \"error\": {\n    \"code\": \"VALIDATION_ERROR\",\n    \"message\": \"Invalid request parameters\",\n    \"details\": [\"Email is required\", \"Password must be at least 8 characters\"]\n  },\n  \"timestamp\": \"2024-01-01T12:00:00Z\",\n  \"requestId\": \"req-123456\"\n}\n```\n\n**Testing Results:**\n- ✅ All error scenarios tested\n- ✅ Proper status codes returned\n- ✅ Error logging implemented\n- ✅ Security information not leaked\n- ✅ User-friendly error messages\n\nError handling is now comprehensive and robust across all API endpoints."}]}}
EOF

    # Test the hook extracts the content correctly
    run bash -c "echo '{\"transcript_path\": \"format_test_transcript.jsonl\"}' | ./gemini-review-hook.sh"
    
    assert_success
    assert_output --partial '"decision"'
    
    # Check that the extracted content contains expected elements
    debug_log="/tmp/gemini-review-debug.log"
    if [ -f "$debug_log" ]; then
        run grep "Successfully extracted Claude summary" "$debug_log"
        assert_success
        
        # Content should be substantial (> 1000 chars for this detailed message)
        run grep -E "Successfully extracted Claude summary \([0-9]{4,} characters\)" "$debug_log"
        assert_success
    fi
}

@test "gemini-review-hook properly limits content length" {
    # Create a very long transcript to test content limiting
    long_content="I've implemented a comprehensive solution with the following details: "
    for i in {1..100}; do
        long_content+="This is section $i with detailed implementation notes and technical specifications. "
    done
    
    cat > long_transcript.jsonl << EOF
{"type": "user", "uuid": "user-001", "message": {"content": [{"type": "text", "text": "Please implement a complex system."}]}}
{"type": "assistant", "uuid": "assistant-001", "message": {"content": [{"type": "text", "text": "$long_content"}]}}
EOF

    # Test the hook with long content
    run bash -c "echo '{\"transcript_path\": \"long_transcript.jsonl\"}' | ./gemini-review-hook.sh"
    
    assert_success
    
    # Check that content was properly limited
    debug_log="/tmp/gemini-review-debug.log"
    if [ -f "$debug_log" ]; then
        # Should show extraction but content should be limited
        run grep "Successfully extracted Claude summary" "$debug_log"
        assert_success
    fi
}
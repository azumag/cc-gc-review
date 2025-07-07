#!/bin/bash
# Comprehensive validation for gemini-review-hook.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_SCRIPT="$PROJECT_ROOT/hooks/gemini-review-hook.sh"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

log_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

# Objective review quality measurement
measure_review_quality() {
    local review_text="$1"
    local git_diff="$2"
    local score=0

    # Minimum length check (100 chars)
    local char_count=$(echo "$review_text" | wc -c)
    if [ "$char_count" -ge 100 ]; then
        ((score++))
    fi

    # File mention check (git diff files referenced)
    if [ -n "$git_diff" ]; then
        local changed_files=$(echo "$git_diff" | grep "^diff --git" | wc -l)
        local mentioned_files=$(echo "$review_text" | grep -c '\.sh\|\.js\|\.py\|\.md\|\.yml\|\.yaml' || true)
        if [ "$mentioned_files" -gt 0 ] && [ "$changed_files" -gt 0 ]; then
            ((score++))
        fi
    fi

    # Improvement suggestion check
    local improvement_mentions=$(echo "$review_text" | grep -c '改善\|修正\|追加\|考慮\|検討' || true)
    if [ "$improvement_mentions" -ge 1 ]; then
        ((score++))
    fi

    # Specific technical terms
    local tech_terms=$(echo "$review_text" | grep -c 'コード\|関数\|変数\|エラー\|テスト' || true)
    if [ "$tech_terms" -ge 2 ]; then
        ((score++))
    fi

    echo "$score"
}

# Validate JSON output
validate_json_output() {
    local output="$1"
    local test_name="$2"

    # Check if valid JSON
    if ! echo "$output" | jq . >/dev/null 2>&1; then
        log_fail "$test_name: Invalid JSON output"
        return 1
    fi

    # Check required fields
    local decision=$(echo "$output" | jq -r '.decision // empty')
    local reason=$(echo "$output" | jq -r '.reason // empty')

    if [ -z "$decision" ] || [ -z "$reason" ]; then
        log_fail "$test_name: Missing required fields (decision/reason)"
        return 1
    fi

    # Check decision values
    if [[ "$decision" != "approve" && "$decision" != "block" ]]; then
        log_fail "$test_name: Invalid decision value: $decision"
        return 1
    fi

    log_pass "$test_name: Valid JSON output"
    return 0
}

# Test Case 1: Normal operation with mock transcript
test_normal_operation() {
    log_test "Testing normal operation"

    local temp_transcript=$(mktemp)
    cat >"$temp_transcript" <<'EOF'
{"type": "assistant", "uuid": "test-001", "message": {"content": [{"type": "text", "text": "I've completed the CI fixes including:\n\n1. Fixed JSON schema validation\n2. Updated git context handling\n3. Improved error handling\n\nAll tests are now passing and validation scripts are in place."}]}}
EOF

    local input="{\"transcript_path\": \"$temp_transcript\"}"
    local output
    local start_time=$(date +%s)

    output=$(timeout 60s bash -c "echo '$input' | '$HOOK_SCRIPT'" 2>/dev/null || echo '{"decision": "block", "reason": "Hook execution failed or timed out"}')
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Validate JSON
    if validate_json_output "$output" "Normal Operation"; then
        # Check response time
        if [ "$duration" -le 120 ]; then
            log_pass "Normal Operation: Response time acceptable ($duration seconds)"
        else
            log_fail "Normal Operation: Response time too slow ($duration seconds)"
        fi

        # Measure review quality
        local reason=$(echo "$output" | jq -r '.reason')
        local git_diff=$(git diff HEAD 2>/dev/null || echo "")
        local quality_score=$(measure_review_quality "$reason" "$git_diff")

        if [ "$quality_score" -ge 2 ]; then
            log_pass "Normal Operation: Review quality acceptable (score: $quality_score/4)"
        else
            log_fail "Normal Operation: Review quality insufficient (score: $quality_score/4)"
        fi
    fi

    rm -f "$temp_transcript"
}

# Test Case 2: Review completed scenario
test_review_completed() {
    log_test "Testing review completed scenario"

    local temp_transcript=$(mktemp)
    cat >"$temp_transcript" <<'EOF'
{"type": "assistant", "uuid": "test-002", "message": {"content": [{"type": "text", "text": "REVIEW_COMPLETED"}]}}
EOF

    local input="{\"transcript_path\": \"$temp_transcript\"}"
    local output=$(echo "$input" | "$HOOK_SCRIPT" 2>/dev/null)

    if validate_json_output "$output" "Review Completed"; then
        local decision=$(echo "$output" | jq -r '.decision')
        if [ "$decision" = "approve" ]; then
            log_pass "Review Completed: Correct decision (approve)"
        else
            log_fail "Review Completed: Wrong decision ($decision, expected approve)"
        fi
    fi

    rm -f "$temp_transcript"
}

# Test Case 3: Rate limited scenario
test_rate_limited() {
    log_test "Testing rate limited scenario"

    local temp_transcript=$(mktemp)
    cat >"$temp_transcript" <<'EOF'
{"type": "assistant", "uuid": "test-003", "message": {"content": [{"type": "text", "text": "REVIEW_RATE_LIMITED"}]}}
EOF

    local input="{\"transcript_path\": \"$temp_transcript\"}"
    local output=$(echo "$input" | "$HOOK_SCRIPT" 2>/dev/null)

    if validate_json_output "$output" "Rate Limited"; then
        local decision=$(echo "$output" | jq -r '.decision')
        if [ "$decision" = "block" ]; then
            log_pass "Rate Limited: Correct decision (block)"
        else
            log_fail "Rate Limited: Wrong decision ($decision, expected block)"
        fi
    fi

    rm -f "$temp_transcript"
}

# Test Case 4: Invalid JSON input
test_invalid_json() {
    log_test "Testing invalid JSON input"

    local invalid_input='{"type": "assistant"'
    local output=$(echo "$invalid_input" | "$HOOK_SCRIPT" 2>/dev/null)

    if validate_json_output "$output" "Invalid JSON"; then
        local decision=$(echo "$output" | jq -r '.decision')
        if [ "$decision" = "block" ]; then
            log_pass "Invalid JSON: Correct error handling"
        else
            log_fail "Invalid JSON: Wrong decision ($decision, expected block)"
        fi
    fi
}

# Test Case 5: Missing transcript file
test_missing_file() {
    log_test "Testing missing transcript file"

    local input='{"transcript_path": "/nonexistent/file.jsonl"}'
    local output=$(echo "$input" | "$HOOK_SCRIPT" 2>/dev/null)

    validate_json_output "$output" "Missing File"
}

# Run all tests
main() {
    echo "=== Gemini Review Hook Validation ==="
    echo "Hook script: $HOOK_SCRIPT"
    echo

    # Check environment first
    if ! "$PROJECT_ROOT/scripts/validate-test-environment.sh" >/dev/null 2>&1; then
        echo -e "${RED}Environment validation failed${NC}"
        exit 1
    fi

    # Run test cases
    test_normal_operation
    test_review_completed
    test_rate_limited
    test_invalid_json
    test_missing_file

    echo
    echo "=== Test Results ==="
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"

    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed${NC}"
        exit 1
    fi
}

main "$@"

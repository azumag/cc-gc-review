#!/bin/bash
# Test script for timeout handling in gemini-review-hook.sh

set -euo pipefail

# Source the shared utilities from hooks directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$(cd "$SCRIPT_DIR/../hooks" && pwd)"
source "$HOOKS_DIR/shared-utils.sh" || {
    echo "Failed to source shared-utils.sh"
    exit 1
}

# Test environment setup
setup_test_env() {
    TEST_DIR=$(mktemp -d)
    export GEMINI_HOOK_LOG_DIR="$TEST_DIR"
    export DEBUG_GEMINI_HOOK=true
    
    # Create a mock gemini command for testing
    MOCK_BIN_DIR="$TEST_DIR/bin"
    mkdir -p "$MOCK_BIN_DIR"
    export PATH="$MOCK_BIN_DIR:$PATH"
}

# Cleanup function
cleanup_test_env() {
    if [ -n "${TEST_DIR:-}" ] && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi
}

trap cleanup_test_env EXIT

# Test 1: Verify timeout configuration is 120 seconds
test_timeout_configuration() {
    echo "Testing: Timeout configuration value"
    
    # Extract GEMINI_TIMEOUT from the hook script
    TIMEOUT_VALUE=$(grep "^readonly GEMINI_TIMEOUT=" "$(dirname "$0")/../hooks/gemini-review-hook.sh" | cut -d= -f2)
    
    if [ "$TIMEOUT_VALUE" = "120" ]; then
        echo "✓ GEMINI_TIMEOUT is correctly set to 120 seconds"
    else
        echo "✗ GEMINI_TIMEOUT is set to $TIMEOUT_VALUE, expected 120"
        return 1
    fi
}

# Test 2: Verify timeout mechanism works correctly
test_timeout_behavior() {
    echo "Testing: Timeout mechanism and error handling"
    
    setup_test_env
    
    # Test 2a: Verify that the timeout configuration is properly read
    echo "  - Verifying timeout configuration is used..."
    
    # Check the script uses timeout command with GEMINI_TIMEOUT
    if grep -q "timeout \${GEMINI_TIMEOUT}s" "$(dirname "$0")/../hooks/gemini-review-hook.sh"; then
        echo "  ✓ Script uses timeout command with GEMINI_TIMEOUT variable"
    else
        echo "  ✗ Timeout command not properly configured"
        return 1
    fi
    
    # Test 2b: Test manual timeout implementation (for systems without timeout command)
    echo "  - Testing manual timeout implementation..."
    
    # Check the script has fallback for systems without timeout command
    if grep -q "kill -0 \$GEMINI_PID" "$(dirname "$0")/../hooks/gemini-review-hook.sh" && \
       grep -q "WAIT_COUNT -lt \$GEMINI_TIMEOUT" "$(dirname "$0")/../hooks/gemini-review-hook.sh"; then
        echo "  ✓ Manual timeout implementation exists for systems without timeout command"
    else
        echo "  ✗ No fallback for systems without timeout command"
        return 1
    fi
    
    # Test 2c: Verify timeout value consistency
    echo "  - Checking timeout value consistency..."
    
    # Count how many times GEMINI_TIMEOUT is used
    TIMEOUT_USAGE_COUNT=$(grep -c "GEMINI_TIMEOUT" "$(dirname "$0")/../hooks/gemini-review-hook.sh" || echo 0)
    
    if [ "$TIMEOUT_USAGE_COUNT" -ge 4 ]; then
        echo "  ✓ GEMINI_TIMEOUT is consistently used throughout the script ($TIMEOUT_USAGE_COUNT occurrences)"
    else
        echo "  ✗ GEMINI_TIMEOUT usage seems insufficient ($TIMEOUT_USAGE_COUNT occurrences)"
        return 1
    fi
    
    
    # Test 2d: Test actual error handling with mock
    echo "  - Testing error handling with mock gemini..."
    
    # Create a simple mock that returns success
    cat > "$MOCK_BIN_DIR/gemini" << 'EOF'
#!/bin/bash
# Mock gemini that returns a simple review
echo "Test review: Code looks good"
exit 0
EOF
    chmod +x "$MOCK_BIN_DIR/gemini"
    
    # Create empty transcript file
    touch "$TEST_DIR/transcript.jsonl"
    
    # Create test input
    TEST_INPUT=$(cat <<EOF
{
    "transcript_path": "$TEST_DIR/transcript.jsonl"
}
EOF
)
    
    echo "$TEST_INPUT" | "$(dirname "$0")/../hooks/gemini-review-hook.sh" > "$TEST_DIR/output.json" 2>"$TEST_DIR/error.log"
    
    # Check output contains proper JSON structure
    if jq -e '.decision' "$TEST_DIR/output.json" >/dev/null 2>&1; then
        echo "  ✓ Script produces valid JSON output"
        DECISION=$(jq -r '.decision' "$TEST_DIR/output.json")
        if [ "$DECISION" = "block" ]; then
            echo "  ✓ Default decision is 'block' as expected"
        else
            echo "  ✗ Unexpected decision value: $DECISION"
            return 1
        fi
    else
        echo "  ✗ Invalid JSON output"
        cat "$TEST_DIR/output.json"
        return 1
    fi
    
    cleanup_test_env
}

# Test 3: Verify Flash model uses same timeout
test_flash_model_timeout() {
    echo "Testing: Flash model timeout consistency"
    
    # Check that flash_timeout variable is not used anymore
    if grep -q "flash_timeout" "$(dirname "$0")/../hooks/gemini-review-hook.sh"; then
        echo "✗ flash_timeout variable still exists in the script"
        return 1
    else
        echo "✓ flash_timeout variable has been removed"
    fi
    
    # Verify Flash model uses GEMINI_TIMEOUT
    if grep -q "timeout \${GEMINI_TIMEOUT}s.*gemini-2.5-flash" "$(dirname "$0")/../hooks/gemini-review-hook.sh"; then
        echo "✓ Flash model correctly uses GEMINI_TIMEOUT"
    else
        echo "✗ Flash model does not use GEMINI_TIMEOUT consistently"
        return 1
    fi
}

# Test 4: Verify command check removal
test_command_check_removal() {
    echo "Testing: Command check removal verification"
    
    # Count occurrences of 'command -v timeout' checks
    CHECK_COUNT=$(grep -c "command -v timeout" "$(dirname "$0")/../hooks/gemini-review-hook.sh" || true)
    
    # Should have at most 2 occurrences (one for Pro, one for Flash)
    if [ "$CHECK_COUNT" -le 2 ]; then
        echo "✓ Command checks are minimal (found $CHECK_COUNT occurrences)"
    else
        echo "✗ Too many command checks found: $CHECK_COUNT"
        return 1
    fi
}

# Run all tests
echo "=== Running Timeout Handling Tests ==="
echo

FAILED=0

test_timeout_configuration || ((FAILED++))
echo

test_timeout_behavior || ((FAILED++))
echo

test_flash_model_timeout || ((FAILED++))
echo

test_command_check_removal || ((FAILED++))
echo

if [ $FAILED -eq 0 ]; then
    echo "=== All tests passed! ==="
    exit 0
else
    echo "=== $FAILED test(s) failed ==="
    exit 1
fi
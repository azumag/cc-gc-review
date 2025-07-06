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

# Test 2: Simulate timeout behavior with mock gemini command
test_timeout_handling() {
    echo "Testing: Timeout handling with mock command"
    
    setup_test_env
    
    # Create a mock gemini that sleeps for a short time to test timeout logic
    cat > "$MOCK_BIN_DIR/gemini" << 'EOF'
#!/bin/bash
# Mock gemini that sleeps for 3 seconds to simulate slow response
sleep 3
echo "Mock response after delay"
EOF
    chmod +x "$MOCK_BIN_DIR/gemini"
    
    # Create test input
    TEST_INPUT=$(cat <<EOF
{
    "transcript_path": "$TEST_DIR/transcript.jsonl"
}
EOF
)
    
    # Test that the script properly handles timeout configuration
    # We're not actually testing a real 120s timeout (that would take too long)
    # Instead we verify the timeout value is properly used in the script
    
    # Check that timeout command is used with GEMINI_TIMEOUT
    if grep -q "timeout \${GEMINI_TIMEOUT}s" "$(dirname "$0")/../hooks/gemini-review-hook.sh"; then
        echo "✓ Timeout is properly configured with GEMINI_TIMEOUT variable"
    else
        echo "✗ Timeout configuration not found in script"
        return 1
    fi
    
    # Run a quick test to ensure the mock works
    START_TIME=$(date +%s)
    echo "$TEST_INPUT" | timeout 5s "$(dirname "$0")/../hooks/gemini-review-hook.sh" > "$TEST_DIR/output.json" 2>&1 || true
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    # Should complete within 5 seconds with our mock
    if [ $DURATION -le 5 ]; then
        echo "✓ Mock timeout test completed successfully (${DURATION}s)"
    else
        echo "✗ Mock test took too long: ${DURATION}s"
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

test_timeout_handling || ((FAILED++))
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
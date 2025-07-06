#!/usr/bin/env bats

load test_helper/bats-support/load
load test_helper/bats-assert/load

setup() {
    TEST_TEMP_DIR=$(mktemp -d -t cc-gc-test-XXXXXX)
    
    # Create test transcript files
    TEST_TRANSCRIPT="$TEST_TEMP_DIR/transcript.json"
    INVALID_TRANSCRIPT="$TEST_TEMP_DIR/invalid.json"
    
    # Valid transcript with assistant message
    cat > "$TEST_TRANSCRIPT" << 'EOF'
[
  {
    "type": "user",
    "message": {"content": [{"type": "text", "text": "Hello"}]}
  },
  {
    "type": "assistant", 
    "message": {
      "content": [
        {"type": "text", "text": "This is a test summary."}
      ]
    }
  }
]
EOF

    # Invalid JSON
    echo 'invalid json' > "$INVALID_TRANSCRIPT"
}

cleanup_test_env() {
    [ -n "$TEST_TEMP_DIR" ] && rm -rf "$TEST_TEMP_DIR"
}

teardown() {
    cleanup_test_env
}

@test "Valid JSON file exists and can be read" {
    [ -f "$TEST_TRANSCRIPT" ]
    run cat "$TEST_TRANSCRIPT"
    assert_success
}

@test "Invalid JSON file exists" {
    [ -f "$INVALID_TRANSCRIPT" ]
    run cat "$INVALID_TRANSCRIPT"
    assert_success
    assert_output "invalid json"
}

@test "jq can parse valid JSON" {
    run jq . "$TEST_TRANSCRIPT"
    assert_success
}

@test "jq fails on invalid JSON" {
    run jq . "$INVALID_TRANSCRIPT"
    assert_failure
}
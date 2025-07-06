#!/usr/bin/env bats

load test_helper/bats-support/load.bash
load test_helper/bats-assert/load.bash
load test_helper/bats-file/load.bash

# Helper function for extracting Claude summary
extract_claude_summary() {
    local file="$1"
    jq -r '[.[] | select(.type == "assistant")] | if length > 0 then .[-1].message.content[]? | select(.type == "text") | .text else empty end' "$file" 2>/dev/null
}

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
        {"type": "text", "text": "This is a test summary of work completed. The changes include improvements to error handling and code quality."}
      ]
    }
  }
]
EOF

    # Invalid JSON
    echo '{"invalid": json}' > "$INVALID_TRANSCRIPT"
}

cleanup_test_env() {
    [ -n "$TEST_TEMP_DIR" ] && rm -rf "$TEST_TEMP_DIR"
}

teardown() {
    cleanup_test_env
}

# Trap will be set within each test

@test "CLAUDE_SUMMARY extraction from valid transcript" {
    # Test the jq command directly
    result=$(extract_claude_summary "$TEST_TRANSCRIPT")
    
    assert_equal "$result" "This is a test summary of work completed. The changes include improvements to error handling and code quality."
}

@test "CLAUDE_SUMMARY extraction from invalid JSON" {
    run extract_claude_summary "$INVALID_TRANSCRIPT"
    
    assert_failure
}

@test "CLAUDE_SUMMARY truncation for long text" {
    # Create transcript with long summary
    LONG_TRANSCRIPT="$TEST_TEMP_DIR/long_transcript.json"
    LONG_TEXT=$(printf 'A%.0s' $(seq 1 1200))  # 1200 character string
    
    cat > "$LONG_TRANSCRIPT" << EOF
[
  {
    "type": "assistant",
    "message": {
      "content": [
        {"type": "text", "text": "${LONG_TEXT}"}
      ]
    }
  }
]
EOF

    # Test truncation logic
    CLAUDE_SUMMARY=$(extract_claude_summary "$LONG_TRANSCRIPT")
    
    # Apply truncation logic
    if [ ${#CLAUDE_SUMMARY} -gt 1000 ]; then
        FIRST_PART=$(echo "$CLAUDE_SUMMARY" | head -c 400)
        LAST_PART=$(echo "$CLAUDE_SUMMARY" | tail -c 400)
        CLAUDE_SUMMARY="${FIRST_PART}...(中略)...${LAST_PART}"
    fi
    
    # Should be truncated
    assert [ ${#CLAUDE_SUMMARY} -le 820 ]  # 400 + 400 + markers
    [[ "$CLAUDE_SUMMARY" == *"...(中略)..."* ]]
}

@test "CLAUDE_SUMMARY empty for no assistant messages" {
    # Create transcript with no assistant messages
    NO_ASSISTANT_TRANSCRIPT="$TEST_TEMP_DIR/no_assistant.json"
    cat > "$NO_ASSISTANT_TRANSCRIPT" << 'EOF'
[
  {
    "type": "user",
    "message": {"content": [{"type": "text", "text": "Hello"}]}
  }
]
EOF

    result=$(extract_claude_summary "$NO_ASSISTANT_TRANSCRIPT")
    
    assert_equal "$result" ""
}

@test "CLAUDE_SUMMARY gets last assistant message when multiple exist" {
    # Create transcript with multiple assistant messages
    MULTI_TRANSCRIPT="$TEST_TEMP_DIR/multi_assistant.json"
    cat > "$MULTI_TRANSCRIPT" << 'EOF'
[
  {
    "type": "assistant",
    "message": {
      "content": [
        {"type": "text", "text": "First message"}
      ]
    }
  },
  {
    "type": "user",
    "message": {"content": [{"type": "text", "text": "User response"}]}
  },
  {
    "type": "assistant",
    "message": {
      "content": [
        {"type": "text", "text": "Last message - this should be extracted"}
      ]
    }
  }
]
EOF

    result=$(extract_claude_summary "$MULTI_TRANSCRIPT")
    
    assert_equal "$result" "Last message - this should be extracted"
}
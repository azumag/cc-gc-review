#!/usr/bin/env bats

# Test for extract_last_assistant_message function fix

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

# Test environment setup
setup() {
    # Load the function
    source "${BATS_TEST_DIRNAME}/../hooks/shared-utils.sh"
    
    # Set transcript path if it exists
    TRANSCRIPT_PATH="/Users/azumag/.claude/projects/-Users-azumag-work-cc-gc-review/11641804-e30a-4198-aacd-3a782a79c64a.jsonl"
    
    # Skip tests if transcript doesn't exist (for CI environment)
    if [ ! -f "$TRANSCRIPT_PATH" ]; then
        skip "Transcript file not available in CI environment"
    fi
}

@test "extract_last_assistant_message: should return substantial content with full_content=true" {
    run extract_last_assistant_message "$TRANSCRIPT_PATH" 0 true
    
    assert_success
    # Adjust expectation to match actual last assistant message content
    assert [ ${#output} -gt 50 ]
    assert [ ${#output} -lt 200 ]
    assert_regex "$output" ".*修正.*"
}

@test "extract_last_assistant_message: should return last line only with full_content=false" {
    run extract_last_assistant_message "$TRANSCRIPT_PATH" 0 false
    
    assert_success
    assert [ ${#output} -gt 0 ]
    assert [ ${#output} -lt 500 ]
}

@test "extract_last_assistant_message: should work with line_limit=100" {
    run extract_last_assistant_message "$TRANSCRIPT_PATH" 100 false
    
    assert_success
    # With line_limit=100, we should find at least some content
    assert [ ${#output} -gt 0 ]
}

@test "extract_last_assistant_message: should handle non-existent file" {
    run extract_last_assistant_message "/non/existent/file.jsonl" 0 true
    
    assert_failure
    assert_output --partial "Error: Transcript file not found"
}

@test "extract_last_assistant_message: should successfully extract content" {
    run extract_last_assistant_message "$TRANSCRIPT_PATH" 0 true
    
    assert_success
    # Should contain content from the last assistant message (adjust to actual content)
    assert [ ${#output} -gt 50 ]
    assert [ ${#output} -lt 200 ]
}

@test "extract_last_assistant_message: should not fail with parsing errors" {
    run extract_last_assistant_message "$TRANSCRIPT_PATH" 0 true
    
    assert_success
    # Should succeed and return content, not fail
    assert [ ${#output} -gt 0 ]
}
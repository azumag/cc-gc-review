#!/usr/bin/env bats

# Test for run_tests.sh script itself

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'
load 'test_helper/bats-file/load'

setup() {
    # Create a temporary test directory
    TEMP_TEST_DIR=$(mktemp -d)
    
    # Copy run_tests.sh to temp directory
    cp "${BATS_TEST_DIRNAME}/run_tests.sh" "$TEMP_TEST_DIR/"
    
    # Create a mock test-config.json
    cat > "$TEMP_TEST_DIR/test-config.json" << 'EOF'
{
  "shell_tests": [
    {
      "file": "mock_passing_test.sh",
      "description": "Mock passing test",
      "category": "mock",
      "timeout": 5,
      "required_dependencies": ["jq"]
    },
    {
      "file": "mock_failing_test.sh", 
      "description": "Mock failing test",
      "category": "mock",
      "timeout": 5,
      "required_dependencies": ["jq"]
    }
  ],
  "error_patterns": {
    "critical": ["FATAL", "CRITICAL"],
    "errors": ["Error:", "FAIL", "Failed"],
    "warnings": ["WARN", "Warning"]
  },
  "output_limits": {
    "max_error_lines": 5,
    "max_error_indicators": 3,
    "max_failed_cases": 2
  }
}
EOF

    # Create mock test scripts
    cat > "$TEMP_TEST_DIR/mock_passing_test.sh" << 'EOF'
#!/bin/bash
echo "Mock test passed"
exit 0
EOF

    cat > "$TEMP_TEST_DIR/mock_failing_test.sh" << 'EOF'
#!/bin/bash
echo "Mock test output" >&1
echo "Failed: Mock assertion failed" >&1
echo "Error: Mock test failed" >&2
echo "FAIL: Mock assertion failed" >&2
exit 1
EOF

    # Make test scripts executable
    chmod +x "$TEMP_TEST_DIR/mock_passing_test.sh"
    chmod +x "$TEMP_TEST_DIR/mock_failing_test.sh"
    
    # Create a simple mock BATS file to avoid "no test files" error
    cat > "$TEMP_TEST_DIR/test_mock.bats" << 'EOF'
#!/usr/bin/env bats
@test "mock test that always passes" {
    true
}
EOF
}

teardown() {
    # Clean up temporary directory
    if [ -d "$TEMP_TEST_DIR" ]; then
        rm -rf "$TEMP_TEST_DIR"
    fi
}

@test "run_tests.sh: should load test configuration successfully" {
    cd "$TEMP_TEST_DIR"
    
    # Test configuration loading by checking help output
    run ./run_tests.sh --help
    
    assert_success
    assert_output --partial "Shell Script Test Runner"
}

@test "run_tests.sh: should fail gracefully when config file is missing" {
    cd "$TEMP_TEST_DIR"
    
    # Remove config file and run tests
    rm -f test-config.json
    
    run ./run_tests.sh
    
    assert_failure
    assert_output --partial "Test configuration file not found"
}

@test "run_tests.sh: should handle malformed JSON config gracefully" {
    cd "$TEMP_TEST_DIR"
    
    # Create malformed JSON config
    echo '{"invalid": json}' > test-config.json
    
    run ./run_tests.sh
    
    assert_failure
    assert_output --partial "Invalid JSON in config file"
}

@test "run_tests.sh: should detect and report test failures with structured output" {
    cd "$TEMP_TEST_DIR"
    
    # Skip test if Bash version is too old for associative arrays
    if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
        skip "Bash 4.0+ required for associative arrays (current: $BASH_VERSION)"
    fi
    
    # Run tests and expect failure due to mock_failing_test.sh
    run ./run_tests.sh
    
    assert_failure
    assert_output --partial "Mock failing test failed"
    assert_output --partial "SHELL TEST FAILURE ANALYSIS"
    assert_output --partial "mock Test Failures"
    assert_output --partial "Error: Mock test failed"
    assert_output --partial "FAIL: Mock assertion failed"
}

@test "run_tests.sh: should separate stdout and stderr correctly" {
    cd "$TEMP_TEST_DIR"
    
    # Skip test if Bash version is too old for associative arrays
    if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
        skip "Bash 4.0+ required for associative arrays (current: $BASH_VERSION)"
    fi
    
    # Run tests and verify output separation
    run ./run_tests.sh
    
    assert_failure
    # Should show stderr errors separately from stdout
    assert_output --partial "Error Output (stderr"
    assert_output --partial "Failed Test Cases"
}

@test "run_tests.sh: should respect timeout settings from config" {
    cd "$TEMP_TEST_DIR"
    
    # Skip test if Bash version is too old for associative arrays
    if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
        skip "Bash 4.0+ required for associative arrays (current: $BASH_VERSION)"
    fi
    
    # Create a test that takes longer than timeout
    cat > mock_timeout_test.sh << 'EOF'
#!/bin/bash
sleep 10
echo "This should not appear"
EOF
    chmod +x mock_timeout_test.sh
    
    # Update config to include timeout test with 1 second timeout
    jq '.shell_tests += [{"file": "mock_timeout_test.sh", "description": "Timeout test", "category": "timeout", "timeout": 1}]' test-config.json > temp_config.json
    mv temp_config.json test-config.json
    
    # Skip if timeout command is not available
    if ! command -v timeout >/dev/null 2>&1; then
        skip "timeout command not available"
    fi
    
    run timeout 15s ./run_tests.sh
    
    assert_failure
    assert_output --partial "Timeout test failed"
}

@test "run_tests.sh: should provide comprehensive debugging information" {
    cd "$TEMP_TEST_DIR"
    
    # Skip test if Bash version is too old for associative arrays
    if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
        skip "Bash 4.0+ required for associative arrays (current: $BASH_VERSION)"
    fi
    
    run ./run_tests.sh
    
    assert_failure
    assert_output --partial "Structured Debugging Guide"
    assert_output --partial "Check dependencies"
    assert_output --partial "Review config"
    assert_output --partial "test-config.json"
}
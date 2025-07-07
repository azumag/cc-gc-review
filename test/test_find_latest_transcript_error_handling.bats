#!/usr/bin/env bats

load test_helper

# Test find_latest_transcript_in_dir error handling
source ../hooks/shared-utils.sh

setup() {
    # Create a unique temporary directory for each test
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
}

teardown() {
    # Clean up temporary directory
    if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
        cd /
        rm -rf "$TEST_DIR"
    fi
}

@test "find_latest_transcript_in_dir returns 1 for non-existent directory" {
    run find_latest_transcript_in_dir "/non/existent/directory"
    assert_equal "$status" 1
    assert_output ""
}

@test "find_latest_transcript_in_dir returns 2 for directory with no jsonl files" {
    mkdir empty_dir
    run find_latest_transcript_in_dir "empty_dir"
    assert_equal "$status" 2
    assert_output ""
}

@test "find_latest_transcript_in_dir returns 0 for directory with jsonl files" {
    mkdir test_dir
    # Create test files with different timestamps
    touch test_dir/old.jsonl
    sleep 1
    touch test_dir/newer.jsonl
    
    run find_latest_transcript_in_dir "test_dir"
    assert_equal "$status" 0
    assert_output --partial "newer.jsonl"
}

@test "find_latest_transcript_in_dir handles debug mode correctly" {
    HOOK_DEBUG=true run find_latest_transcript_in_dir "/non/existent/directory"
    assert_equal "$status" 1
    assert_output --partial "DEBUG: Directory not found"
}

@test "find_latest_transcript_in_dir processes multiple files correctly" {
    mkdir multi_dir
    # Create multiple files with different timestamps  
    touch multi_dir/file1.jsonl
    sleep 1
    touch multi_dir/file2.jsonl
    sleep 1
    touch multi_dir/file3.jsonl
    
    run find_latest_transcript_in_dir "multi_dir"
    assert_equal "$status" 0
    assert_output --partial "file3.jsonl"
}

@test "find_latest_transcript_in_dir ignores non-jsonl files" {
    mkdir mixed_dir
    touch mixed_dir/ignore.txt
    touch mixed_dir/also_ignore.log
    touch mixed_dir/target.jsonl
    
    run find_latest_transcript_in_dir "mixed_dir"
    assert_equal "$status" 0
    assert_output --partial "target.jsonl"
}

@test "find_latest_transcript_in_dir provides detailed error messages" {
    mkdir error_test_dir
    touch error_test_dir/test.jsonl
    
    # Create a scenario that will definitely trigger an error by mocking find to fail
    export PATH="$TEST_DIR:$PATH"
    cat > find << 'EOF'
#!/bin/bash
# Mock find that fails when executing stat
if [[ "$*" == *"-exec stat"* ]]; then
    echo "find: stat failed: No such file or directory" >&2
    exit 1
else
    # Normal find behavior for file existence check
    exec /usr/bin/find "$@"
fi
EOF
    chmod +x find
    
    # Test with debug mode
    HOOK_DEBUG=true run find_latest_transcript_in_dir "error_test_dir"
    assert_equal "$status" 3
    
    # Should contain detailed error information in debug message
    assert_output --partial "DEBUG: stat command failed on"
    assert_output --partial "(exit code: 1):"
    assert_output --partial "No such file or directory"
}

@test "find_latest_transcript_in_dir handles successful stat with empty output" {
    mkdir empty_stat_dir
    touch empty_stat_dir/test.jsonl
    
    # Create a mock find command that succeeds but produces no output
    export PATH="$TEST_DIR:$PATH"
    cat > find << 'EOF'
#!/bin/bash
# Mock find that succeeds but produces no output for stat
if [[ "$*" == *"-exec stat"* ]]; then
    # Simulate successful find but empty stat output (exit 0 but no output)
    exit 0
else
    # Normal find behavior for file existence check
    exec /usr/bin/find "$@"
fi
EOF
    chmod +x find
    
    # Test with debug mode - this should trigger the "succeeded but no output" message
    HOOK_DEBUG=true run find_latest_transcript_in_dir "empty_stat_dir"
    assert_equal "$status" 3
    
    # Should contain the specific message for successful command with empty output
    assert_output --partial "DEBUG: stat command succeeded but produced no output despite files existing in:"
    assert_output --partial "empty_stat_dir"
}

@test "find_latest_transcript_in_dir handles mktemp failure gracefully" {
    mkdir mktemp_fail_dir
    touch mktemp_fail_dir/test.jsonl
    
    # Create a mock mktemp command that always fails
    export PATH="$TEST_DIR:$PATH"
    cat > mktemp << 'EOF'
#!/bin/bash
# Mock mktemp that always fails
echo "mktemp: cannot create temp file" >&2
exit 1
EOF
    chmod +x mktemp
    
    # Test with debug mode - should use fallback error handling
    HOOK_DEBUG=true run find_latest_transcript_in_dir "mktemp_fail_dir"
    assert_equal "$status" 0
    
    # Should contain the fallback message about not being able to create temp file
    assert_output --partial "DEBUG: Cannot create temp file for detailed error capture, using basic error handling"
    
    # Should still find the file successfully despite mktemp failure
    assert_output --partial "test.jsonl"
}
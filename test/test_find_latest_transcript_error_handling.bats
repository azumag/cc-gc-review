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

@test "find_latest_transcript_in_dir returns 3 when stat command fails" {
    mkdir stat_fail_dir
    touch stat_fail_dir/test.jsonl
    
    # Create a mock stat command that fails
    export PATH="$TEST_DIR:$PATH"
    cat > stat << 'EOF'
#!/bin/bash
# Mock stat that always fails with specific error pattern
echo "stat: cannot access files" >&2
exit 1
EOF
    chmod +x stat
    
    # Test with debug mode to see the error message
    HOOK_DEBUG=true run find_latest_transcript_in_dir "stat_fail_dir"
    assert_equal "$status" 3
    
    # The mock stat command causes empty output, triggering the "No stat output received" path
    # This is the expected behavior when stat command fails
    assert_output --partial "DEBUG: No stat output received despite files existing"
}

@test "find_latest_transcript_in_dir handles empty stat output gracefully" {
    mkdir empty_stat_dir
    touch empty_stat_dir/test.jsonl
    
    # Create a mock find command that succeeds but produces no output
    export PATH="$TEST_DIR:$PATH"
    cat > find << 'EOF'
#!/bin/bash
# Mock find that succeeds but produces no output for stat
if [[ "$*" == *"-exec stat"* ]]; then
    # Simulate successful find but empty stat output
    exit 0
else
    # Normal find behavior for file existence check
    exec /usr/bin/find "$@"
fi
EOF
    chmod +x find
    
    # Test with debug mode
    HOOK_DEBUG=true run find_latest_transcript_in_dir "empty_stat_dir"
    assert_equal "$status" 3
    assert_output --partial "DEBUG: No stat output received despite files existing"
}
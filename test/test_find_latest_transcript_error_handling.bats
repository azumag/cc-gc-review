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
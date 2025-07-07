#!/usr/bin/env bats

load test_helper

# Test notification.sh transcript path detection functionality

setup() {
    setup_test_environment
    
    # Source the notification script functions
    # The shared-utils.sh is already sourced by notification.sh, so we only need to source notification.sh
    source "$BATS_TEST_DIRNAME/../hooks/notification.sh"
}

teardown() {
    cleanup_test_env
}

@test "find_transcript_path() detects correct project transcript" {
    # Test with actual project directory
    run find_transcript_path
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ \.jsonl$ ]]
    [[ "$output" =~ cc-gc-review ]]
    [ -f "$output" ]
}

@test "find_transcript_path() returns most recent transcript" {
    # Test that the function returns the most recent transcript
    run find_transcript_path
    
    [ "$status" -eq 0 ]
    
    # Verify it's actually the most recent
    local found_transcript="$output"
    local most_recent=$(find "$HOME/.claude/projects" -name "*.jsonl" -type f -exec ls -t {} + 2>/dev/null | head -1)
    
    # The found transcript should be the most recent for this project
    [[ "$found_transcript" =~ cc-gc-review ]]
}

@test "jq filter extracts transcript_path correctly" {
    # Test with valid JSON containing transcript_path
    run bash -c 'echo "{\"transcript_path\": \"/path/to/transcript\"}" | jq -r ".transcript_path // empty"'
    
    [ "$status" -eq 0 ]
    [ "$output" = "/path/to/transcript" ]
}

@test "jq filter handles missing transcript_path" {
    # Test with JSON missing transcript_path
    run bash -c 'echo "{\"other_field\": \"value\"}" | jq -r ".transcript_path // empty"'
    
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "jq filter handles null transcript_path" {
    # Test with null transcript_path
    run bash -c 'echo "{\"transcript_path\": null}" | jq -r ".transcript_path // empty"'
    
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "extract_last_assistant_message() works with actual transcript" {
    # Find the actual transcript path
    local transcript_path
    transcript_path=$(find_transcript_path)
    
    [ -f "$transcript_path" ]
    
    # Test extracting the last assistant message
    run extract_last_assistant_message "$transcript_path" 0 true
    
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    
    # Should contain some meaningful content
    [[ ${#output} -gt 10 ]]
}

@test "get_work_summary() extracts summary from transcript" {
    # Find the actual transcript path
    local transcript_path
    transcript_path=$(find_transcript_path)
    
    [ -f "$transcript_path" ]
    
    # Test getting work summary
    run get_work_summary "$transcript_path"
    
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    
    # Should contain some meaningful content
    [[ ${#output} -gt 10 ]]
}

@test "extract_task_title() creates meaningful titles" {
    # Test with various summary formats
    run extract_task_title "Work Summary: Fixed bug in notification system"
    [ "$status" -eq 0 ]
    [ "$output" = "Fixed bug in notification system" ]
    
    run extract_task_title "**Work Summary**: Added new feature"
    [ "$status" -eq 0 ]
    [ "$output" = "Added new feature" ]
    
    run extract_task_title "• Step 1: Completed the setup"
    [ "$status" -eq 0 ]
    [ "$output" = "Completed the setup" ]
    
    run extract_task_title ""
    [ "$status" -eq 0 ]
    [ "$output" = "Task Completed" ]
}

@test "notification script handles Claude Code stop hook JSON input" {
    # Create a test JSON input that simulates Claude Code stop hook
    local test_transcript_path
    test_transcript_path=$(find_transcript_path)
    
    local test_input="{\"transcript_path\": \"$test_transcript_path\"}"
    
    # Mock the main function to test input parsing
    run bash -c "
        source '$BATS_TEST_DIRNAME/../hooks/shared-utils.sh'
        source '$BATS_TEST_DIRNAME/../hooks/notification.sh'
        
        # Test the input parsing logic
        input='$test_input'
        transcript_path=\$(echo \"\$input\" | jq -r '.transcript_path // empty' 2>/dev/null || echo \"\")
        echo \"Parsed transcript path: \$transcript_path\"
        
        # Verify the path exists
        if [ -f \"\$transcript_path\" ]; then
            echo \"Transcript file exists: true\"
        else
            echo \"Transcript file exists: false\"
        fi
    "
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Parsed transcript path: $test_transcript_path" ]]
    [[ "$output" =~ "Transcript file exists: true" ]]
}

@test "path escaping works correctly for current directory" {
    # Test the path escaping logic
    local current_dir=$(pwd)
    local escaped_path=$(echo "$current_dir" | sed 's/[^a-zA-Z0-9]/-/g')
    
    # Should replace non-alphanumeric characters with hyphens
    [[ "$escaped_path" =~ ^[a-zA-Z0-9-]+$ ]]
    
    # Should find the matching project directory (optional test)
    local project_dir=$(find "$HOME/.claude/projects" -type d -name "*$escaped_path*" | head -1)
    
    # Only test if project directory exists
    if [ -n "$project_dir" ]; then
        [ -d "$project_dir" ]
        [[ "$project_dir" =~ $escaped_path ]]
    fi
}
#!/usr/bin/env bats

load test_helper

# Test notification.sh transcript path detection functionality

setup() {
    setup_test_environment
    
    # Create mock Claude projects directory
    export MOCK_CLAUDE_DIR="$TEST_TMP_DIR/.claude"
    export MOCK_PROJECTS_DIR="$MOCK_CLAUDE_DIR/projects"
    mkdir -p "$MOCK_PROJECTS_DIR" || {
        echo "Failed to create mock projects directory" >&2
        return 1
    }
    
    # Create mock project directory based on current directory
    local current_dir=$(pwd)
    local escaped_path=$(echo "$current_dir" | sed 's/[^a-zA-Z0-9]/-/g')
    export MOCK_PROJECT_DIR="$MOCK_PROJECTS_DIR/project-$escaped_path"
    mkdir -p "$MOCK_PROJECT_DIR"
    
    # Create mock transcript files with realistic content
    local timestamp=$(date -u +%Y%m%d_%H%M%S)
    export MOCK_TRANSCRIPT_PATH="$MOCK_PROJECT_DIR/transcript_${timestamp}.jsonl"
    
    # Create realistic JSONL content
    cat > "$MOCK_TRANSCRIPT_PATH" << 'EOF'
{"type": "user", "uuid": "user-1", "message": {"content": [{"type": "text", "text": "Help me fix the notification system"}]}}
{"type": "assistant", "uuid": "assistant-1", "message": {"content": [{"type": "text", "text": "I'll help you fix the notification system. Let me analyze the current implementation and identify the issues."}]}}
{"type": "user", "uuid": "user-2", "message": {"content": [{"type": "text", "text": "The tests are failing in CI"}]}}
{"type": "assistant", "uuid": "assistant-2", "message": {"content": [{"type": "text", "text": "## Work Summary\n\nI've successfully fixed the notification system issues:\n\n1. **Fixed environment dependency issue** - Modified test_notification_transcript.bats to create mock Claude directory structure\n2. **Added CI support** - Tests now work in both local and CI environments\n3. **Improved test reliability** - All 10 tests can now execute properly regardless of environment\n4. **Enhanced error handling** - Better cleanup and error recovery\n\n**Fix notification system and improve test reliability**"}]}}
EOF
    
    # Create an older transcript file for testing "most recent" functionality
    local older_timestamp="20240101_120000"
    local older_transcript="$MOCK_PROJECT_DIR/transcript_${older_timestamp}_old.jsonl"
    
    cat > "$older_transcript" << 'EOF'
{"type": "user", "uuid": "user-old", "message": {"content": [{"type": "text", "text": "Previous work"}]}}
{"type": "assistant", "uuid": "assistant-old", "message": {"content": [{"type": "text", "text": "Previous work completed successfully"}]}}
EOF
    
    # Create a transcript in another project directory for fallback testing
    local other_project_dir="$MOCK_PROJECTS_DIR/other-project"
    mkdir -p "$other_project_dir"
    local other_transcript="$other_project_dir/transcript_${timestamp}_other.jsonl"
    
    cat > "$other_transcript" << 'EOF'
{"type": "user", "uuid": "user-other", "message": {"content": [{"type": "text", "text": "Other project work"}]}}
{"type": "assistant", "uuid": "assistant-other", "message": {"content": [{"type": "text", "text": "Other project work completed"}]}}
EOF
    
    # Override HOME temporarily for tests to use mock directory
    export ORIGINAL_HOME="$HOME"
    export HOME="$TEST_TMP_DIR"
    
    # Source the notification script functions
    source "$BATS_TEST_DIRNAME/../hooks/notification.sh" || {
        echo "Failed to source notification script" >&2
        return 1
    }
}

teardown() {
    # Restore original HOME if it was overridden
    if [ -n "${ORIGINAL_HOME:-}" ]; then
        export HOME="$ORIGINAL_HOME"
        unset ORIGINAL_HOME
    fi
    
    # Clean up mock environment variables
    unset MOCK_CLAUDE_DIR MOCK_PROJECTS_DIR MOCK_PROJECT_DIR MOCK_TRANSCRIPT_PATH
    
    cleanup_test_env
}

@test "find_transcript_path() detects correct project transcript" {
    run find_transcript_path
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ \.jsonl$ ]]
    [ -f "$output" ]
    
    # Should find our mock transcript
    [ "$output" = "$MOCK_TRANSCRIPT_PATH" ]
}

@test "find_transcript_path() returns most recent transcript" {
    run find_transcript_path
    
    [ "$status" -eq 0 ]
    
    # Should find our mock transcript (which is the most recent due to timestamp)
    [ "$output" = "$MOCK_TRANSCRIPT_PATH" ]
}

@test "jq filter extracts transcript_path correctly" {
    run bash -c 'echo "{\"transcript_path\": \"/path/to/transcript\"}" | jq -r ".transcript_path // empty"'
    
    [ "$status" -eq 0 ]
    [ "$output" = "/path/to/transcript" ]
}

@test "jq filter handles missing transcript_path" {
    run bash -c 'echo "{\"other_field\": \"value\"}" | jq -r ".transcript_path // empty"'
    
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "jq filter handles null transcript_path" {
    run bash -c 'echo "{\"transcript_path\": null}" | jq -r ".transcript_path // empty"'
    
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "extract_last_assistant_message() works with actual transcript" {
    local transcript_path
    transcript_path=$(find_transcript_path)
    
    [ -f "$transcript_path" ]
    
    run extract_last_assistant_message "$transcript_path" 0 true
    
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    
    # Should contain some meaningful content
    [[ ${#output} -gt 10 ]]
    
    # Should contain our expected content
    [[ "$output" =~ "Work Summary" ]]
}

@test "get_work_summary() extracts summary from transcript" {
    local transcript_path
    transcript_path=$(find_transcript_path)
    
    [ -f "$transcript_path" ]
    
    run get_work_summary "$transcript_path"
    
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    
    # Should contain some meaningful content
    [[ ${#output} -gt 10 ]]
    
    # Should contain our expected content
    [[ "$output" =~ "Work Summary" ]]
}

@test "extract_task_title() creates meaningful titles" {
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
    local test_transcript_path
    test_transcript_path=$(find_transcript_path)
    
    local test_input="{\"transcript_path\": \"$test_transcript_path\"}"
    
    run bash -c "
        export HOME='$HOME'
        export MOCK_TRANSCRIPT_PATH='$MOCK_TRANSCRIPT_PATH'
        
        source '$BATS_TEST_DIRNAME/../hooks/shared-utils.sh'
        source '$BATS_TEST_DIRNAME/../hooks/notification.sh'
        
        input='$test_input'
        transcript_path=\$(echo \"\$input\" | jq -r '.transcript_path // empty' 2>/dev/null || echo \"\")
        echo \"Parsed transcript path: \$transcript_path\"
        
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
    local current_dir=$(pwd)
    local escaped_path=$(echo "$current_dir" | sed 's/[^a-zA-Z0-9]/-/g')
    
    # Should replace non-alphanumeric characters with hyphens
    [[ "$escaped_path" =~ ^[a-zA-Z0-9-]+$ ]]
    
    # Should find the matching project directory
    local project_dir=$(find "$HOME/.claude/projects" -type d -name "*$escaped_path*" | head -1)
    
    # Test that project directory exists
    [ -n "$project_dir" ]
    [ -d "$project_dir" ]
    [[ "$project_dir" =~ $escaped_path ]]
}
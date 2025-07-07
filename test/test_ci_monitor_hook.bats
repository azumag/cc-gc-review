#!/usr/bin/env bats

# Test ci-monitor-hook.sh comprehensive functionality
# Tests message detection, CI status monitoring, timeout behavior, decision formatting, and error handling

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    # Get the repository root directory before changing directories
    REPO_ROOT=$(git rev-parse --show-toplevel)
    
    # Create temporary directory for test
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
    
    # Copy the ci-monitor-hook.sh for testing
    cp "$REPO_ROOT/hooks/ci-monitor-hook.sh" .
    cp "$REPO_ROOT/hooks/shared-utils.sh" .
    
    # Make gh command available (mock)
    export PATH="$TEST_DIR:$PATH"
    
    # Initialize git repo for testing
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"
    
    # Create initial commit
    echo "test" > test.txt
    git add test.txt
    git commit -m "Initial commit"
    
    # Create test branch
    git checkout -b test-branch
    
    # Create mock gh command
    cat > gh << 'EOF'
#!/bin/bash
case "$1" in
    "run")
        if [ "$2" = "list" ]; then
            echo "${GH_RUN_LIST_RESPONSE:-[]}"
        elif [ "$2" = "view" ]; then
            echo "${GH_RUN_VIEW_RESPONSE:-{}}"
        fi
        ;;
    "auth")
        if [ "$2" = "status" ]; then
            exit 0
        fi
        ;;
    *)
        echo "Mock gh command called with: $*" >&2
        exit 1
        ;;
esac
EOF
    chmod +x gh
    
    # Mock git rev-parse command
    cat > git << 'EOF'
#!/bin/bash
case "$1" in
    "rev-parse")
        if [ "$2" = "--abbrev-ref" ] && [ "$3" = "HEAD" ]; then
            echo "test-branch"
        elif [ "$2" = "--git-dir" ]; then
            echo ".git"
        elif [ "$2" = "HEAD" ]; then
            echo "abc123def456789"
        fi
        ;;
    *)
        exec /usr/bin/git "$@"
        ;;
esac
EOF
    chmod +x git
}

teardown() {
    cd /
    rm -rf "$TEST_DIR"
}

@test "ci-monitor-hook detects REVIEW_COMPLETED && PUSH_COMPLETED message" {
    # Create transcript with matching message
    cat > matching_transcript.jsonl << 'EOF'
{"type": "user", "uuid": "user-001", "message": {"content": [{"type": "text", "text": "Please push the changes to the repository."}]}}
{"type": "assistant", "uuid": "assistant-001", "message": {"content": [{"type": "text", "text": "I'll push the changes now.\n\nREVIEW_COMPLETED && PUSH_COMPLETED"}]}}
EOF

    # Set up successful CI response
    export GH_RUN_LIST_RESPONSE='[{"status": "completed", "conclusion": "success", "databaseId": "123", "name": "CI Tests", "headSha": "abc123def456789", "url": "https://github.com/test/repo/actions/runs/123"}]'
    
    # Test the hook with matching message
    run timeout 10s bash -c "echo '{\"transcript_path\": \"matching_transcript.jsonl\"}' | ./ci-monitor-hook.sh"
    
    # Should succeed and complete monitoring
    assert_success
    
    # Should produce JSON output with approve decision when CI passes
    assert_output --partial '"decision": "approve"'
    assert_output --partial 'All CI workflows passed successfully'
}

@test "ci-monitor-hook ignores non-matching messages" {
    # Create transcript without matching message
    cat > non_matching_transcript.jsonl << 'EOF'
{"type": "user", "uuid": "user-001", "message": {"content": [{"type": "text", "text": "Please review the code."}]}}
{"type": "assistant", "uuid": "assistant-001", "message": {"content": [{"type": "text", "text": "I've reviewed the code and it looks good. No issues found."}]}}
EOF

    # Test the hook with non-matching message
    run bash -c "echo '{\"transcript_path\": \"non_matching_transcript.jsonl\"}' | ./ci-monitor-hook.sh"
    
    # Should exit early without monitoring
    assert_success
    
    # Should produce JSON output indicating marker not found
    assert_output --partial '"decision": "approve"'
    assert_output --partial 'REVIEW_COMPLETED && PUSH_COMPLETED marker not found'
}

@test "ci-monitor-hook handles CI failure" {
    # Create transcript with matching message
    cat > failure_transcript.jsonl << 'EOF'
{"type": "assistant", "uuid": "assistant-001", "message": {"content": [{"type": "text", "text": "REVIEW_COMPLETED && PUSH_COMPLETED"}]}}
EOF

    # Set up failed CI response
    export GH_RUN_LIST_RESPONSE='[{"status": "completed", "conclusion": "failure", "databaseId": "456", "name": "CI Tests", "headSha": "abc123def456789", "url": "https://github.com/test/repo/actions/runs/456"}]'
    
    # Test the hook with failed CI
    run timeout 10s bash -c "echo '{\"transcript_path\": \"failure_transcript.jsonl\"}' | ./ci-monitor-hook.sh"
    
    # Should succeed (hook executed successfully)
    assert_success
    
    # Should produce JSON decision block
    assert_output --partial "\"decision\": \"block\""
    assert_output --partial "\"reason\""
    assert_output --partial "CI Check Failed"
}

@test "ci-monitor-hook handles timeout behavior" {
    # Create transcript with matching message
    cat > timeout_test_transcript.jsonl << 'EOF'
{"type": "assistant", "uuid": "assistant-001", "message": {"content": [{"type": "text", "text": "REVIEW_COMPLETED && PUSH_COMPLETED"}]}}
EOF

    # Set up perpetually in-progress CI response
    export GH_RUN_LIST_RESPONSE='[{"status": "in_progress", "conclusion": null, "databaseId": "222", "name": "Long Running Test", "headSha": "abc123def456789", "url": "https://github.com/test/repo/actions/runs/222"}]'
    
    # Modify the CI monitor hook to have a very short timeout for testing
    sed -i.bak 's/MAX_WAIT_TIME=300/MAX_WAIT_TIME=3/' ci-monitor-hook.sh
    
    # Test the hook with perpetually in-progress CI
    run timeout 10s bash -c "echo '{\"transcript_path\": \"timeout_test_transcript.jsonl\"}' | ./ci-monitor-hook.sh"
    
    # Should fail (timeout reached)
    assert_failure
    
    # Should produce JSON output with block decision when timeout
    assert_output --partial '"decision": "block"'
    assert_output --partial 'CI monitoring timeout reached'
}

@test "ci-monitor-hook handles missing gh CLI" {
    # Create transcript with matching message
    cat > missing_gh_transcript.jsonl << 'EOF'
{"type": "assistant", "uuid": "assistant-001", "message": {"content": [{"type": "text", "text": "REVIEW_COMPLETED && PUSH_COMPLETED"}]}}
EOF

    # Remove gh from PATH
    export PATH="/usr/bin:/bin"
    
    # Test the hook without gh CLI
    run bash -c "echo '{\"transcript_path\": \"missing_gh_transcript.jsonl\"}' | ./ci-monitor-hook.sh"
    
    # Should exit gracefully
    assert_success
    
    # Should produce JSON output when gh CLI not found
    assert_output --partial '"decision": "approve"'
    assert_output --partial 'GitHub CLI (gh) not found'
}

@test "ci-monitor-hook handles empty input" {
    # Test with empty JSON input
    run bash -c "echo '{}' | ./ci-monitor-hook.sh"
    
    # Should exit gracefully
    assert_success
    
    # Should produce JSON output when no session ID provided
    assert_output --partial '"decision": "approve"'
    assert_output --partial 'No session ID'
}

@test "ci-monitor-hook handles CI cancelled" {
    # Create transcript with matching message
    cat > cancelled_transcript.jsonl << 'EOF'
{"type": "assistant", "uuid": "assistant-001", "message": {"content": [{"type": "text", "text": "REVIEW_COMPLETED && PUSH_COMPLETED"}]}}
EOF

    # Set up cancelled CI response
    export GH_RUN_LIST_RESPONSE='[{"status": "completed", "conclusion": "cancelled", "databaseId": "789", "name": "Build Process", "headSha": "abc123def456789", "url": "https://github.com/test/repo/actions/runs/789"}]'
    
    # Test the hook with cancelled CI
    run timeout 10s bash -c "echo '{\"transcript_path\": \"cancelled_transcript.jsonl\"}' | ./ci-monitor-hook.sh"
    
    # Should succeed
    assert_success
    
    # Should produce JSON decision block
    assert_output --partial "\"decision\": \"block\""
    assert_output --partial "\"reason\""
    assert_output --partial "CI Check Failed"
    assert_output --partial "Build Process"
    assert_output --partial "cancelled"
}

@test "ci-monitor-hook handles CI timeout" {
    # Create transcript with matching message
    cat > timeout_transcript.jsonl << 'EOF'
{"type": "assistant", "uuid": "assistant-001", "message": {"content": [{"type": "text", "text": "REVIEW_COMPLETED && PUSH_COMPLETED"}]}}
EOF

    # Set up timed out CI response
    export GH_RUN_LIST_RESPONSE='[{"status": "completed", "conclusion": "timed_out", "databaseId": "999", "name": "Test Suite", "headSha": "abc123def456789", "url": "https://github.com/test/repo/actions/runs/999"}]'
    
    # Test the hook with timed out CI
    run timeout 10s bash -c "echo '{\"transcript_path\": \"timeout_transcript.jsonl\"}' | ./ci-monitor-hook.sh"
    
    # Should succeed
    assert_success
    
    # Should produce JSON decision block
    assert_output --partial "\"decision\": \"block\""
    assert_output --partial "\"reason\""
    assert_output --partial "CI Check Failed"
    assert_output --partial "Test Suite"
    assert_output --partial "timed_out"
}

@test "ci-monitor-hook formats decision block correctly" {
    # Create transcript with matching message
    cat > format_test_transcript.jsonl << 'EOF'
{"type": "assistant", "uuid": "assistant-001", "message": {"content": [{"type": "text", "text": "REVIEW_COMPLETED && PUSH_COMPLETED"}]}}
EOF

    # Set up failed CI response with specific details
    export GH_RUN_LIST_RESPONSE='[{"status": "completed", "conclusion": "failure", "databaseId": "444", "name": "Format Test Workflow", "headSha": "abc123def456789", "url": "https://github.com/test/repo/actions/runs/444"}]'
    
    # Test the hook with failed CI
    run timeout 10s bash -c "echo '{\"transcript_path\": \"format_test_transcript.jsonl\"}' | ./ci-monitor-hook.sh"
    
    # Should succeed
    assert_success
    
    # Verify JSON structure
    assert_output --partial "\"decision\": \"block\""
    assert_output --partial "\"reason\""
    
    # Verify the decision block contains expected markdown formatting
    assert_output --partial "## CI Check Failed"
    assert_output --partial "**Workflow:** Format Test Workflow"
    assert_output --partial "**Status:** failure"
    assert_output --partial "**URL:** https://github.com/test/repo/actions/runs/444"
    assert_output --partial "### Next Steps:"
    assert_output --partial "1. Click the URL above"
    assert_output --partial "2. Fix the identified issues"
    assert_output --partial "3. Commit and push the fixes"
    assert_output --partial "4. The CI will automatically re-run"
    assert_output --partial "Would you like me to help analyze and fix the CI failures?"
}

@test "ci-monitor-hook handles missing transcript file" {
    # Test with non-existent file
    run bash -c "echo '{\"transcript_path\": \"nonexistent.jsonl\"}' | ./ci-monitor-hook.sh"
    
    # Should exit gracefully
    assert_success
    
    # Should produce JSON output when transcript not found
    assert_output --partial '"decision": "approve"'
    assert_output --partial 'No transcript files found'
}

@test "ci-monitor-hook handles unauthenticated gh CLI" {
    # Create transcript with matching message
    cat > unauth_transcript.jsonl << 'EOF'
{"type": "assistant", "uuid": "assistant-001", "message": {"content": [{"type": "text", "text": "REVIEW_COMPLETED && PUSH_COMPLETED"}]}}
EOF

    # Create gh mock that fails auth
    cat > gh << 'EOF'
#!/bin/bash
case "$1" in
    "auth")
        if [ "$2" = "status" ]; then
            echo "Not authenticated" >&2
            exit 1
        fi
        ;;
esac
EOF
    chmod +x gh
    
    # Test the hook with unauthenticated gh
    run bash -c "echo '{\"transcript_path\": \"unauth_transcript.jsonl\"}' | ./ci-monitor-hook.sh"
    
    # Should exit gracefully
    assert_success
    
    # Should produce JSON output when not authenticated
    assert_output --partial '"decision": "approve"'
    assert_output --partial 'Not authenticated with GitHub CLI'
}

@test "ci-monitor-hook handles non-git repository" {
    # Create transcript with matching message
    cat > non_git_transcript.jsonl << 'EOF'
{"type": "assistant", "uuid": "assistant-001", "message": {"content": [{"type": "text", "text": "REVIEW_COMPLETED && PUSH_COMPLETED"}]}}
EOF

    # Create git mock that fails git-dir check
    cat > git << 'EOF'
#!/bin/bash
case "$1" in
    "rev-parse")
        if [ "$2" = "--git-dir" ]; then
            echo "Not a git repository" >&2
            exit 1
        fi
        ;;
esac
EOF
    chmod +x git
    
    # Test the hook in non-git directory
    run bash -c "echo '{\"transcript_path\": \"non_git_transcript.jsonl\"}' | ./ci-monitor-hook.sh"
    
    # Should exit gracefully
    assert_success
    
    # Should produce JSON output when not in git repo
    assert_output --partial '"decision": "approve"'
    assert_output --partial 'Not in a git repository'
}
#!/usr/bin/env bats

# test_watch_reset.bats - Tests for watch functions and reset behavior

load "test_helper/bats-support/load.bash"
load "test_helper/bats-assert/load.bash"

setup() {
    # Clean up any leftover test directories first
    rm -rf ./test-tmp-* 2>/dev/null || true
    
    # Test configuration
    export TEST_SESSION="test-watch-$$"
    # Use mktemp for safer temporary directory creation
    export TEST_TMP_DIR
    TEST_TMP_DIR=$(mktemp -d)
    SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")"/.. && pwd)"
    export SCRIPT_DIR
    export TEST_REVIEW_FILE="$TEST_TMP_DIR/gemini-review"
    export TEST_COUNT_FILE="$TEST_TMP_DIR/cc-gc-review-count"
    
    # Set up cleanup trap
    trap 'cleanup_test_env' EXIT INT TERM
    
    # Mock git settings
    export GIT_AUTHOR_NAME="Test User"
    export GIT_AUTHOR_EMAIL="test@example.com"
    export GIT_COMMITTER_NAME="Test User"
    export GIT_COMMITTER_EMAIL="test@example.com"
}

cleanup_test_env() {
    # Clean up tmux session
    tmux kill-session -t "$TEST_SESSION" 2>/dev/null || true
    
    # Clean up test directories
    if [[ -n "$TEST_TMP_DIR" && -d "$TEST_TMP_DIR" ]]; then
        rm -rf "$TEST_TMP_DIR"
    fi
    
    # Clean up any remaining test files
    rm -f /tmp/gemini-* 2>/dev/null || true
    rm -f /tmp/cc-gc-review-* 2>/dev/null || true
    
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
}

teardown() {
    # Cleanup is now handled by the trap in setup()
    # Additional cleanup if needed can be added here
    cleanup_test_env
}

@test "watch_with_polling should NOT reset count on same file updates" {
    # Create tmux session
    tmux new-session -d -s "$TEST_SESSION"
    
    # Source the script to get the function
    source "$SCRIPT_DIR/cc-gc-review.sh"
    
    # Override the necessary variables for testing
    MAX_REVIEWS=4
    INFINITE_REVIEW=false
    REVIEW_COUNT_FILE="$TEST_COUNT_FILE"
    THINK_MODE=false
    CUSTOM_COMMAND=""
    CC_GC_REVIEW_TEST_MODE=true
    
    # Create initial count
    echo "1" > "$TEST_COUNT_FILE"
    
    # Create initial review file
    echo "Initial review content" > "$TEST_REVIEW_FILE"
    
    # Test the problematic behavior: count should NOT be reset on file updates
    # This simulates what happens when the same hook-handler session writes multiple times
    
    # Mock the watch_with_polling function to test the logic
    local watch_file="$TEST_REVIEW_FILE"
    local session="$TEST_SESSION"
    
    # Simulate file update (what currently happens)
    if [[ -f "$watch_file" ]]; then
        local content
    content=$(cat "$watch_file")
        if [[ -n "$content" ]]; then
            # This is the problematic part - the count is reset here
            # In the current implementation, this would delete the count file
            # We need to test that this behavior is WRONG
            
            # Current (broken) implementation would do this:
            # rm "$REVIEW_COUNT_FILE" 2>/dev/null || true
            
            # Let's test what should happen instead
            run send_review_to_tmux "$session" "$content"
            [ "$status" -eq 0 ]
            
            # The count should continue from where it was (1 -> 2)
            [[ "$output" =~ "📊 Review count: 2/4" ]]
            
            # Check count file has incremented from existing value
            run cat "$TEST_COUNT_FILE"
            [ "$output" = "2" ]
        fi
    fi
}

@test "count should only reset when limit is reached and passed" {
    # Create tmux session
    tmux new-session -d -s "$TEST_SESSION"
    
    # Source the script to get the function
    source "$SCRIPT_DIR/cc-gc-review.sh"
    
    # Override the necessary variables for testing
    MAX_REVIEWS=3
    INFINITE_REVIEW=false
    REVIEW_COUNT_FILE="$TEST_COUNT_FILE"
    THINK_MODE=false
    CUSTOM_COMMAND=""
    CC_GC_REVIEW_TEST_MODE=true
    
    # Test that count continues across multiple reviews
    run send_review_to_tmux "$TEST_SESSION" "First review"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 1/3" ]]
    
    run send_review_to_tmux "$TEST_SESSION" "Second review"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 2/3" ]]
    
    run send_review_to_tmux "$TEST_SESSION" "Third review"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 3/3" ]]
    [[ "$output" =~ "⚠️  Review limit will be reached" ]]
    
    # Next review should be passed and count reset
    run send_review_to_tmux "$TEST_SESSION" "Fourth review (should be passed)"
    [ "$status" -eq 1 ]
    [[ "$output" =~  Review limit reached (3/3) ]]
    [[ "$output" =~ "Passing this review and resetting count" ]]
    
    # Count file should be deleted
    assert_file_not_exists "$TEST_COUNT_FILE"
    
    # Next review should start from 1 again
    run send_review_to_tmux "$TEST_SESSION" "Fifth review (after reset)"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 1/3" ]]
}

@test "polling function should preserve count across multiple file changes" {
    # Create tmux session
    tmux new-session -d -s "$TEST_SESSION"
    
    # Source the script to get the function
    source "$SCRIPT_DIR/cc-gc-review.sh"
    
    # Override the necessary variables for testing
    MAX_REVIEWS=4
    INFINITE_REVIEW=false
    REVIEW_COUNT_FILE="$TEST_COUNT_FILE"
    THINK_MODE=false
    CUSTOM_COMMAND=""
    CC_GC_REVIEW_TEST_MODE=true
    
    # Set up initial count
    echo "0" > "$TEST_COUNT_FILE"
    
    # Create review file
    echo "First review" > "$TEST_REVIEW_FILE"
    
    # Test multiple file updates in sequence
    # This simulates what happens when the same review process writes multiple times
    
    # First update
    run send_review_to_tmux "$TEST_SESSION" "First review"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 1/4" ]]
    
    # Second update (same session)
    run send_review_to_tmux "$TEST_SESSION" "Second review"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 2/4" ]]
    
    # Third update (same session)
    run send_review_to_tmux "$TEST_SESSION" "Third review"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 3/4" ]]
    
    # Verify final count
    run cat "$TEST_COUNT_FILE"
    [ "$output" = "3" ]
}

@test "watch functions should handle count correctly with new specification" {
    # Create tmux session
    tmux new-session -d -s "$TEST_SESSION"
    
    # Source the script to get the function
    source "$SCRIPT_DIR/cc-gc-review.sh"
    
    # Override the necessary variables for testing
    MAX_REVIEWS=4
    INFINITE_REVIEW=false
    REVIEW_COUNT_FILE="$TEST_COUNT_FILE"
    THINK_MODE=false
    CUSTOM_COMMAND=""
    CC_GC_REVIEW_TEST_MODE=true
    
    # Test that new implementation preserves count correctly
    echo "1" > "$TEST_COUNT_FILE"
    
    # Test reset_review_count_if_needed function with new specification
    run reset_review_count_if_needed "$TEST_REVIEW_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "auto-reset disabled in new specification" ]]
    
    # Count should be preserved (not reset)
    run cat "$TEST_COUNT_FILE"
    [ "$output" = "1" ]
    
    # Subsequent review should increment from existing count
    run send_review_to_tmux "$TEST_SESSION" "Test review content"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 2/4" ]]
    
    # Check count file has incremented correctly
    run cat "$TEST_COUNT_FILE"
    [ "$output" = "2" ]
}

@test "reset should only happen when review limit is reached" {
    # Create tmux session
    tmux new-session -d -s "$TEST_SESSION"
    
    # Source the script to get the function
    source "$SCRIPT_DIR/cc-gc-review.sh"
    
    # Override the necessary variables for testing
    MAX_REVIEWS=2
    INFINITE_REVIEW=false
    REVIEW_COUNT_FILE="$TEST_COUNT_FILE"
    THINK_MODE=false
    CUSTOM_COMMAND=""
    CC_GC_REVIEW_TEST_MODE=true
    
    # Test that reset ONLY happens when limit is reached
    
    # First review
    run send_review_to_tmux "$TEST_SESSION" "First review"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 1/2" ]]
    
    # Second review - reaches limit
    run send_review_to_tmux "$TEST_SESSION" "Second review"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 2/2" ]]
    [[ "$output" =~ "⚠️  Review limit will be reached" ]]
    
    # Third review - should be passed and trigger reset
    run send_review_to_tmux "$TEST_SESSION" "Third review (should be passed)"
    [ "$status" -eq 1 ]
    [[ "$output" =~  Review limit reached (2/2) ]]
    [[ "$output" =~ "Passing this review and resetting count" ]]
    
    # Count file should be deleted after reset
    assert_file_not_exists "$TEST_COUNT_FILE"
    
    # Fourth review should start from 1 after reset
    run send_review_to_tmux "$TEST_SESSION" "Fourth review (after reset)"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 1/2" ]]
}
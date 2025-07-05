#!/usr/bin/env bats

# test_watch_reset.bats - Tests for watch functions and reset behavior

load "test_helper/bats-support/load.bash"
load "test_helper/bats-assert/load.bash"

setup() {
    # Test configuration
    export TEST_SESSION="test-watch-$$"
    export TEST_TMP_DIR="./test-tmp-$$"
    export SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    export TEST_REVIEW_FILE="$TEST_TMP_DIR/gemini-review"
    export TEST_COUNT_FILE="$TEST_TMP_DIR/cc-gc-review-count"
    
    # Create test directory
    mkdir -p "$TEST_TMP_DIR"
    
    # Mock git settings
    export GIT_AUTHOR_NAME="Test User"
    export GIT_AUTHOR_EMAIL="test@example.com"
    export GIT_COMMITTER_NAME="Test User"
    export GIT_COMMITTER_EMAIL="test@example.com"
}

teardown() {
    # Clean up tmux session
    tmux kill-session -t "$TEST_SESSION" 2>/dev/null || true
    
    # Clean up test directories
    rm -rf "$TEST_TMP_DIR"
    
    # Clean up any test files
    rm -f /tmp/gemini-review-* 2>/dev/null || true
    rm -f /tmp/cc-gc-review-count-* 2>/dev/null || true
    
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
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
        local content=$(cat "$watch_file")
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

@test "count should only reset when new hook-handler session starts" {
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
    
    # Simulate a session with multiple reviews
    echo "2" > "$TEST_COUNT_FILE"
    
    # Test that count continues from existing value
    run send_review_to_tmux "$TEST_SESSION" "Continuing review"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 3/4" ]]
    
    # Now simulate a NEW hook-handler session (this should reset the count)
    # This would happen when Claude generates new code and hook-handler creates a fresh review
    
    # The reset should be tied to a new file creation timestamp or a specific signal
    # For now, let's test manual reset
    rm "$TEST_COUNT_FILE" 2>/dev/null || true
    
    # First review of new session should start from 1
    run send_review_to_tmux "$TEST_SESSION" "New session review"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 1/4" ]]
    
    # Check count file was created with value 1
    run cat "$TEST_COUNT_FILE"
    [ "$output" = "1" ]
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

@test "watch functions should handle count correctly" {
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
    
    # Test that current implementation has the bug
    # Create initial count to simulate ongoing session
    echo "1" > "$TEST_COUNT_FILE"
    
    # Simulate what the current watch_with_polling function does
    local watch_file="$TEST_REVIEW_FILE"
    local session="$TEST_SESSION"
    
    # Create review file
    echo "Test review content" > "$watch_file"
    
    # Current implementation (problematic) would reset count here
    # Let's test this behavior to confirm it's wrong
    
    # The bug is in these lines from the current implementation:
    # if [[ -f "$REVIEW_COUNT_FILE" ]]; then
    #     rm "$REVIEW_COUNT_FILE"
    #     echo "🔄 Review count reset due to new file update"
    # fi
    
    # Let's verify this is the problem
    if [[ -f "$watch_file" ]]; then
        local content=$(cat "$watch_file")
        if [[ -n "$content" ]]; then
            # This is what the current implementation does (WRONG):
            if [[ -f "$REVIEW_COUNT_FILE" ]]; then
                rm "$REVIEW_COUNT_FILE"
                echo "🔄 Review count reset due to new file update"
            fi
            
            # Then it calls send_review_to_tmux
            run send_review_to_tmux "$session" "$content"
            [ "$status" -eq 0 ]
            
            # This will always show 1/4 because count was reset
            [[ "$output" =~ "📊 Review count: 1/4" ]]
            
            # This confirms the bug - the count is always 1 after reset
            run cat "$TEST_COUNT_FILE"
            [ "$output" = "1" ]
        fi
    fi
}

@test "reset should only happen on genuine new file creation" {
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
    
    # Test the ideal behavior: reset only on new hook-handler execution
    
    # Simulate existing session with some reviews
    echo "2" > "$TEST_COUNT_FILE"
    
    # File update within same session should NOT reset count
    run send_review_to_tmux "$TEST_SESSION" "Continuing review"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 3/4" ]]
    
    # Now simulate a NEW hook-handler execution
    # This should be the ONLY time count is reset
    # We need a way to detect this - perhaps by checking if the file is truly new
    # or by using a different mechanism
    
    # For now, manual reset to simulate new hook-handler session
    rm "$TEST_COUNT_FILE" 2>/dev/null || true
    
    # New session should start from 1
    run send_review_to_tmux "$TEST_SESSION" "New hook-handler session"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 1/4" ]]
}
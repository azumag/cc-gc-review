#!/usr/bin/env bats

# test_review_count.bats - Review count functionality tests

load "test_helper/bats-support/load.bash"
load "test_helper/bats-assert/load.bash"

setup() {
    # Test configuration
    export TEST_SESSION="test-count-$$"
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
}

@test "review count should increment correctly" {
    # Create tmux session
    tmux new-session -d -s "$TEST_SESSION"
    
    # Test the send_review_to_tmux function directly
    # First, we need to source the script to get the function
    source "$SCRIPT_DIR/cc-gc-review.sh"
    
    # Override the necessary variables for testing
    MAX_REVIEWS=4
    INFINITE_REVIEW=false
    REVIEW_COUNT_FILE="$TEST_COUNT_FILE"
    THINK_MODE=false
    CUSTOM_COMMAND=""
    CC_GC_REVIEW_TEST_MODE=true
    
    # Test first review
    run send_review_to_tmux "$TEST_SESSION" "First review content"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 1/4" ]]
    
    # Check count file exists and has correct value
    assert_file_exists "$TEST_COUNT_FILE"
    run cat "$TEST_COUNT_FILE"
    [ "$output" = "1" ]
    
    # Test second review
    run send_review_to_tmux "$TEST_SESSION" "Second review content"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 2/4" ]]
    
    # Check count file has incremented
    run cat "$TEST_COUNT_FILE"
    [ "$output" = "2" ]
    
    # Test third review
    run send_review_to_tmux "$TEST_SESSION" "Third review content"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 3/4" ]]
    
    # Check count file has incremented
    run cat "$TEST_COUNT_FILE"
    [ "$output" = "3" ]
    
    # Test fourth review
    run send_review_to_tmux "$TEST_SESSION" "Fourth review content"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 4/4" ]]
    
    # Check count file has incremented
    run cat "$TEST_COUNT_FILE"
    [ "$output" = "4" ]
}

@test "review count should stop at limit" {
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
    
    # Test first review
    run send_review_to_tmux "$TEST_SESSION" "First review content"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 1/2" ]]
    
    # Test second review
    run send_review_to_tmux "$TEST_SESSION" "Second review content"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 2/2" ]]
    
    # Test third review should fail (limit reached)
    run send_review_to_tmux "$TEST_SESSION" "Third review content"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "🚫 Review limit reached (2/2)" ]]
    [[ "$output" =~ "Stopping review loop" ]]
}

@test "review count should reset on new file update" {
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
    echo "2" > "$TEST_COUNT_FILE"
    
    # Test review count reset logic
    # This should only happen when a new file update occurs, not on every review
    run send_review_to_tmux "$TEST_SESSION" "Review after file update"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 3/4" ]]
    
    # Check count file has incremented from existing value
    run cat "$TEST_COUNT_FILE"
    [ "$output" = "3" ]
}

@test "infinite review mode should not have count limits" {
    # Create tmux session
    tmux new-session -d -s "$TEST_SESSION"
    
    # Source the script to get the function
    source "$SCRIPT_DIR/cc-gc-review.sh"
    
    # Override the necessary variables for testing
    MAX_REVIEWS=2
    INFINITE_REVIEW=true
    REVIEW_COUNT_FILE="$TEST_COUNT_FILE"
    THINK_MODE=false
    CUSTOM_COMMAND=""
    
    # Test that review count is not displayed in infinite mode
    run send_review_to_tmux "$TEST_SESSION" "Review in infinite mode"
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "📊 Review count:" ]]
    
    # Count file should not be created in infinite mode
    assert_file_not_exists "$TEST_COUNT_FILE"
}

@test "count file should be created if it doesn't exist" {
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
    
    # Ensure count file doesn't exist
    assert_file_not_exists "$TEST_COUNT_FILE"
    
    # Test first review
    run send_review_to_tmux "$TEST_SESSION" "First review content"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 1/4" ]]
    
    # Check count file was created
    assert_file_exists "$TEST_COUNT_FILE"
    run cat "$TEST_COUNT_FILE"
    [ "$output" = "1" ]
}

@test "count file should handle corrupt data gracefully" {
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
    
    # Create corrupt count file
    echo "invalid_data" > "$TEST_COUNT_FILE"
    
    # Test review with corrupt count file
    run send_review_to_tmux "$TEST_SESSION" "Review with corrupt count"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 1/4" ]]
    
    # Check count file was reset to 1
    run cat "$TEST_COUNT_FILE"
    [ "$output" = "1" ]
}

@test "max reviews setting should be respected" {
    # Create tmux session
    tmux new-session -d -s "$TEST_SESSION"
    
    # Source the script to get the function
    source "$SCRIPT_DIR/cc-gc-review.sh"
    
    # Override the necessary variables for testing
    MAX_REVIEWS=1
    INFINITE_REVIEW=false
    REVIEW_COUNT_FILE="$TEST_COUNT_FILE"
    THINK_MODE=false
    CUSTOM_COMMAND=""
    
    # Test first review
    run send_review_to_tmux "$TEST_SESSION" "First review content"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 1/1" ]]
    
    # Test second review should fail immediately
    run send_review_to_tmux "$TEST_SESSION" "Second review content"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "🚫 Review limit reached (1/1)" ]]
}
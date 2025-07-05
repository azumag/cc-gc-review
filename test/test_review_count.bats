#!/usr/bin/env bats

# test_review_count.bats - Review count functionality tests

load 'bats-support'
load 'bats-assert'

setup() {
    # Clean up any leftover test directories first
    rm -rf ./test-tmp-* 2>/dev/null || true
    
    # Test configuration
    export TEST_SESSION="test-count-$$"
    # Use mktemp for safer temporary directory creation
    export TEST_TMP_DIR
    TEST_TMP_DIR=$(mktemp -d)
    SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")"/.. && pwd)"
    export SCRIPT_DIR
    export TEST_REVIEW_FILE="$TEST_TMP_DIR/gemini-review"
    export TEST_COUNT_FILE="$TEST_TMP_DIR/cc-gc-review-count"
    
    # Set up cleanup trap
    trap 'cleanup_test_env' EXIT INT TERM
    
    # CI環境対応
    if [ "${CI:-false}" = "true" ]; then
        export TMUX_TMPDIR=/tmp
        export TERM=xterm-256color
        # CI環境での長めの待機時間
        export BATS_TEST_TIMEOUT=30
    fi
    
    # Mock git settings
    export GIT_AUTHOR_NAME="Test User"
    export GIT_AUTHOR_EMAIL="test@example.com"
    export GIT_COMMITTER_NAME="Test User"
    export GIT_COMMITTER_EMAIL="test@example.com"
}

cleanup_test_env() {
    # Clean up tmux session with retry
    local retry_count=0
    while [ $retry_count -lt 3 ] && tmux has-session -t "$TEST_SESSION" 2>/dev/null; do
        tmux kill-session -t "$TEST_SESSION" 2>/dev/null || true
        sleep 1
        ((retry_count++))
    done
    
    # Clean up test directories
    if [[ -n "$TEST_TMP_DIR" && -d "$TEST_TMP_DIR" ]]; then
        rm -rf "$TEST_TMP_DIR"
    fi
    
    # Clean up any remaining test files
    rm -f /tmp/gemini-* 2>/dev/null || true
    rm -f /tmp/cc-gc-review-* 2>/dev/null || true
}

teardown() {
    # Cleanup is now handled by the trap in setup()
    # Additional cleanup if needed can be added here
    cleanup_test_env
}

@test "review count should increment correctly" {
    # CI環境でのtmuxセッション作成の堅牢性向上
    local session_created=false
    local retry_count=0
    
    while [ $retry_count -lt 3 ] && [ "$session_created" = false ]; do
        if tmux new-session -d -s "$TEST_SESSION" 2>/dev/null; then
            session_created=true
        else
            sleep 2
            ((retry_count++))
        fi
    done
    
    [ "$session_created" = true ] || skip "Could not create tmux session"
    
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

@test "review count should pass at limit and reset" {
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
    
    # Test first review
    run send_review_to_tmux "$TEST_SESSION" "First review content"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 1/2" ]]
    
    # Test second review
    run send_review_to_tmux "$TEST_SESSION" "Second review content"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 2/2" ]]
    [[ "$output" =~ "⚠️  Review limit will be reached" ]]
    
    # Test third review should be passed (limit reached) and count reset
    run send_review_to_tmux "$TEST_SESSION" "Third review content"
    [ "$status" -eq 1 ]
    [[ "$output" =~ Review\ limit\ reached\ \(1/1\) ]]
    [[ "$output" =~ "Passing this review and resetting count" ]]
    [[ "$output" =~ "🔄 Review count reset" ]]
    
    # Count file should be deleted (reset)
    assert_file_not_exists "$TEST_COUNT_FILE"
    
    # Test fourth review should work normally (after reset)
    run send_review_to_tmux "$TEST_SESSION" "Fourth review content"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 1/2" ]]
}

@test "review count should not reset on new file update" {
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
    
    # Set up initial count to simulate previous reviews
    echo "2" > "$TEST_COUNT_FILE"
    
    # Test that review count continues from existing value (no auto-reset on file update)
    run send_review_to_tmux "$TEST_SESSION" "Review after file update"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 3/4" ]]
    
    # Check count file has incremented from existing value (not reset)
    run cat "$TEST_COUNT_FILE"
    [ "$output" = "3" ]
    
    # Test reset_review_count_if_needed function doesn't reset
    run reset_review_count_if_needed "test-file-path"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "auto-reset disabled in new specification" ]]
    
    # Count should remain unchanged
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
    CC_GC_REVIEW_TEST_MODE=true
    
    # Test first review
    run send_review_to_tmux "$TEST_SESSION" "First review content"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 1/1" ]]
    [[ "$output" =~ "⚠️  Review limit will be reached" ]]
    
    # Count should be at limit
    run cat "$TEST_COUNT_FILE"
    [ "$output" = "1" ]
    
    # Test second review should be passed (limit reached) and reset count
    run send_review_to_tmux "$TEST_SESSION" "Second review content"
    [ "$status" -eq 1 ]
    [[ "$output" =~ Review\ limit\ reached\ \(1/1\) ]]
    [[ "$output" =~ "Passing this review and resetting count" ]]
    
    # Count file should be deleted after reset
    assert_file_not_exists "$TEST_COUNT_FILE"
    
    # Test third review should work normally after reset
    run send_review_to_tmux "$TEST_SESSION" "Third review content"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📊 Review count: 1/1" ]]
}

@test "count file should handle invalid values gracefully" {
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
    
    # Test with extremely large value
    echo "99999" > "$TEST_COUNT_FILE"
    
    run send_review_to_tmux "$TEST_SESSION" "Review with large count"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Warning: Invalid count value '99999', resetting to 0" ]]
    [[ "$output" =~ "📊 Review count: 1/4" ]]
    
    # Test with negative value  
    echo "-5" > "$TEST_COUNT_FILE"
    
    run send_review_to_tmux "$TEST_SESSION" "Review with negative count"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Warning: Invalid count value '-5', resetting to 0" ]]
    [[ "$output" =~ "📊 Review count: 1/4" ]]
}

@test "zero max reviews should disable counting" {
    # Create tmux session
    tmux new-session -d -s "$TEST_SESSION"
    
    # Source the script to get the function
    source "$SCRIPT_DIR/cc-gc-review.sh"
    
    # Override the necessary variables for testing
    export MAX_REVIEWS=0
    export INFINITE_REVIEW=false
    export REVIEW_COUNT_FILE="$TEST_COUNT_FILE"
    export THINK_MODE=false
    export CUSTOM_COMMAND=""
    export CC_GC_REVIEW_TEST_MODE=true
    
    # All reviews should be passed immediately when MAX_REVIEWS=0
    run send_review_to_tmux "$TEST_SESSION" "First review with zero limit"
    [ "$status" -eq 1 ]
    [[ "$output" =~ Review\ limit\ reached\ \(0/0\) ]]
    [[ "$output" =~ "Passing this review and resetting count" ]]
    
    # Count file should not exist
    assert_file_not_exists "$TEST_COUNT_FILE"
}
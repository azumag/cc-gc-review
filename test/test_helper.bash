#!/usr/bin/env bash

# test_helper.bash - Common test helper setup for all test files
# This file ensures consistent loading of BATS helper libraries

# Get the directory of this helper file
TEST_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set up BATS_LIB_PATH if not already set
if [[ -z "${BATS_LIB_PATH}" ]]; then
    export BATS_LIB_PATH="${TEST_HELPER_DIR}/test_helper/bats-support:${TEST_HELPER_DIR}/test_helper/bats-assert:${TEST_HELPER_DIR}/test_helper/bats-file"
fi

# Load helper libraries with proper error handling
load_helper() {
    local helper="$1"
    local helper_path="${TEST_HELPER_DIR}/test_helper/${helper}/load.bash"
    
    if [[ -f "$helper_path" ]]; then
        source "$helper_path"
    else
        echo "Error: Helper library not found: $helper_path" >&2
        echo "Please run: cd test && git clone --depth 1 https://github.com/bats-core/${helper}.git test_helper/${helper}" >&2
        return 1
    fi
}

# Load all required helper libraries
load_helper "bats-support" || exit 1
load_helper "bats-assert" || exit 1
load_helper "bats-file" || exit 1

# Common test setup function
setup_test_environment() {
    # Create a safe temporary directory
    export TEST_TMP_DIR
    TEST_TMP_DIR=$(mktemp -d)
    
    # Set up script directory
    export SCRIPT_DIR
    SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")"/.. && pwd)"
    
    # Set up cleanup trap
    trap 'cleanup_test_env' EXIT INT TERM
    
    # Set common environment variables
    export CC_GC_REVIEW_VERBOSE="true"
    export CC_GC_REVIEW_TMP_DIR="$TEST_TMP_DIR"
    
    # Mock git settings for tests
    export GIT_AUTHOR_NAME="Test User"
    export GIT_AUTHOR_EMAIL="test@example.com"
    export GIT_COMMITTER_NAME="Test User"
    export GIT_COMMITTER_EMAIL="test@example.com"
    
    # CI environment settings
    if [ "${CI:-false}" = "true" ]; then
        export TMUX_TMPDIR=/tmp
        export TERM=xterm-256color
    fi
}

# Common cleanup function
cleanup_test_env() {
    # Clean up test tmux sessions if TEST_SESSION is defined
    if [[ -n "${TEST_SESSION:-}" ]]; then
        # Clean up tmux session with retry
        local retry_count=0
        while [ $retry_count -lt 3 ] && tmux has-session -t "$TEST_SESSION" 2>/dev/null; do
            tmux kill-session -t "$TEST_SESSION" 2>/dev/null || true
            sleep 1
            ((retry_count++))
        done
    fi
    
    # Clean up test directories
    if [[ -n "$TEST_TMP_DIR" && -d "$TEST_TMP_DIR" ]]; then
        rm -rf "$TEST_TMP_DIR"
    fi
    
    # Clean up any remaining test files
    rm -f /tmp/gemini-* 2>/dev/null || true
    rm -f /tmp/cc-gc-review-* 2>/dev/null || true
    
    # Clean up environment variables
    unset CC_GC_REVIEW_VERBOSE CC_GC_REVIEW_TMP_DIR CC_GC_REVIEW_WATCH_FILE TEST_SESSION
}
#!/bin/bash

# run_tests.sh - テスト実行スクリプト

set -euo pipefail

# 色付き出力
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# スクリプトのディレクトリを取得
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$TEST_DIR"

echo -e "${BLUE}=== Shell Script Test Runner ===${NC}"
echo "Test directory: $TEST_DIR"

# 使用方法の表示
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f, --file FILE     Run specific test file"
    echo "  -t, --test NAME     Run specific test (pattern match)"
    echo "  -v, --verbose       Verbose output (use --verbose-run for detailed BATS output)"
    echo "  -p, --parallel      Run tests in parallel"
    echo "  -h, --help          Show this help"
    echo ""
    echo "Test Types:"
    echo "  BATS tests          Automated unit tests (*.bats files)"
    echo "  Shell script tests  Integration tests for notification and gemini systems"
    echo ""
    echo "Examples:"
    echo "  $0                                      # Run all tests (BATS + shell scripts)"
    echo "  $0 -f test_extract_last_assistant_message.bats  # Run specific BATS file"
    echo "  $0 -t 'extract_last_assistant'          # Run tests matching pattern"
    echo "  $0 -v                                   # Verbose shell output"
    echo "  $0 -p                                   # Parallel BATS execution"
    echo "  $0 --verbose-run                        # Detailed BATS output for debugging"
}

# デフォルト値
TEST_FILE=""
TEST_PATTERN=""
VERBOSE=false
PARALLEL=false
VERBOSE_RUN=false

# 引数の解析
while [[ $# -gt 0 ]]; do
    case $1 in
    -f | --file)
        TEST_FILE="$2"
        shift 2
        ;;
    -t | --test)
        TEST_PATTERN="$2"
        shift 2
        ;;
    -v | --verbose)
        VERBOSE=true
        shift
        ;;
    --verbose-run)
        VERBOSE_RUN=true
        shift
        ;;
    -p | --parallel)
        PARALLEL=true
        shift
        ;;
    -h | --help)
        show_usage
        exit 0
        ;;
    *)
        echo -e "${RED}Unknown option: $1${NC}"
        show_usage
        exit 1
        ;;
    esac
done

# テスト前のクリーンアップ
cleanup_before_test() {
    echo -e "${YELLOW}Cleaning up test environment...${NC}"

    # 既存のテスト用tmuxセッションを終了
    tmux list-sessions 2>/dev/null | grep "test-claude" | cut -d: -f1 | xargs -I {} tmux kill-session -t {} 2>/dev/null || true

    # テスト用一時ファイルを削除
    rm -rf ./test-tmp-* 2>/dev/null || true
    rm -f /tmp/gemini-review* 2>/dev/null || true
    rm -f /tmp/gemini-prompt* 2>/dev/null || true
    rm -f /tmp/cc-gc-review-* 2>/dev/null || true

    # mktemp で作成された一時ディレクトリも削除
    find /tmp -maxdepth 1 -name "tmp.*" -type d -user "$(whoami)" -mtime +1 -exec rm -rf {} + 2>/dev/null || true

    echo -e "${GREEN}✓ Cleanup completed${NC}"
}

# CI環境の検出と対応
setup_ci_environment() {
    if [ "${CI:-false}" = "true" ]; then
        echo -e "${YELLOW}CI environment detected, applying CI-specific settings...${NC}"

        # CI環境でのtmuxの初期化
        export TMUX_TMPDIR=/tmp

        # CI環境での表示設定
        export TERM=xterm-256color

        # Batsヘルパーライブラリの自動セットアップ
        if [ ! -d "test_helper/bats-support" ] || [ ! -d "test_helper/bats-assert" ] || [ ! -d "test_helper/bats-file" ]; then
            echo -e "${YELLOW}Setting up bats helper libraries for CI...${NC}"
            mkdir -p test_helper

            # bats-supportをダウンロード
            if [ ! -d "test_helper/bats-support" ]; then
                git clone --depth 1 https://github.com/bats-core/bats-support.git test_helper/bats-support
            fi

            # bats-assertをダウンロード
            if [ ! -d "test_helper/bats-assert" ]; then
                git clone --depth 1 https://github.com/bats-core/bats-assert.git test_helper/bats-assert
            fi

            # bats-fileをダウンロード
            if [ ! -d "test_helper/bats-file" ]; then
                git clone --depth 1 https://github.com/bats-core/bats-file.git test_helper/bats-file
            fi
        fi

        echo -e "${GREEN}✓ CI environment setup completed${NC}"
    fi
}

# CI環境のセットアップ（早期実行）
setup_ci_environment

# Batsヘルパーライブラリのパスを設定（CI/ローカル両方で）
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export BATS_LIB_PATH="${SCRIPT_DIR}/test_helper/bats-support:${SCRIPT_DIR}/test_helper/bats-assert:${SCRIPT_DIR}/test_helper/bats-file:${BATS_LIB_PATH:-}"

# 必要なツールの確認
if ! command -v bats >/dev/null 2>&1; then
    echo -e "${RED}Error: bats is not installed${NC}"
    echo "Please run: ./setup_test.sh"
    exit 1
fi

# テスト実行
run_tests() {
    local bats_options=""

    if [ "$VERBOSE" = true ] || [ "$VERBOSE_RUN" = true ]; then
        bats_options="--verbose-run"
    fi

    if [ "$PARALLEL" = true ]; then
        bats_options="$bats_options --jobs 4"
    fi

    if [ -n "$TEST_FILE" ]; then
        if [ ! -f "$TEST_FILE" ]; then
            echo -e "${RED}Error: Test file not found: $TEST_FILE${NC}"
            exit 1
        fi
        echo -e "${YELLOW}Running specific test file: $TEST_FILE${NC}"
        if [ -n "$TEST_PATTERN" ]; then
            bats "$bats_options" --filter "$TEST_PATTERN" "$TEST_FILE"
        else
            bats "$bats_options" "$TEST_FILE"
        fi
    else
        echo -e "${YELLOW}Running all test files...${NC}"
        
        # Run BATS tests
        if [ -n "$TEST_PATTERN" ]; then
            bats "$bats_options" --filter "$TEST_PATTERN" test_*.bats
        else
            bats "$bats_options" test_*.bats
        fi
        
        local bats_exit_code=$?
        local shell_tests_exit_code=0
        
        # Define shell script tests to run - flexible configuration
        local shell_tests=(
            "test_notification_core.sh:Notification core tests"
            "test_gemini_content_only.sh:Gemini hook integration tests"
            "test_notification_examples.sh:Notification workflow examples"
        )
        
        # Track test results with associative arrays for better maintainability
        declare -A test_results
        declare -A test_outputs
        
        # Run each shell script test
        for test_spec in "${shell_tests[@]}"; do
            local test_file="${test_spec%:*}"
            local test_description="${test_spec#*:}"
            
            echo -e "\n${YELLOW}Running $test_description...${NC}"
            
            local test_output
            if test_output=$(./"$test_file" 2>&1); then
                echo -e "${GREEN}✓ $test_description passed${NC}"
                test_results["$test_file"]="PASSED"
            else
                echo -e "${RED}✗ $test_description failed${NC}"
                test_results["$test_file"]="FAILED"
                test_outputs["$test_file"]="$test_output"
                shell_tests_exit_code=1
            fi
        done
        
        # Report detailed failure information if any tests failed
        if [ "$shell_tests_exit_code" -ne 0 ]; then
            echo -e "\n${RED}=== SHELL TEST FAILURE DETAILS ===${NC}"
            
            for test_file in "${!test_results[@]}"; do
                if [ "${test_results[$test_file]}" = "FAILED" ]; then
                    echo -e "\n${RED}Failed Test: $test_file${NC}"
                    
                    local test_output="${test_outputs[$test_file]}"
                    if [ -n "$test_output" ]; then
                        echo -e "${YELLOW}Error Output (last 10 lines):${NC}"
                        echo "$test_output" | tail -n 10 | sed 's/^/  /'
                        
                        # Look for specific error patterns
                        local error_lines
                        if error_lines=$(echo "$test_output" | grep -E "(assertion failed|Test failed|Error:|✗|FAIL|Failed)" | head -5); then
                            echo -e "${YELLOW}Key Error Indicators:${NC}"
                            echo "$error_lines" | sed 's/^/  🔍 /'
                        fi
                        
                        # Extract test case failures if available
                        local failed_cases
                        if failed_cases=$(echo "$test_output" | grep -E "^(✗|FAIL)" | head -3); then
                            echo -e "${YELLOW}Failed Test Cases:${NC}"
                            echo "$failed_cases" | sed 's/^/  📋 /'
                        fi
                    else
                        echo -e "${YELLOW}No detailed output captured${NC}"
                    fi
                    
                    echo -e "${BLUE}$(printf '%.0s-' {1..50})${NC}"
                fi
            done
            
            echo -e "\n${YELLOW}Debugging Guide:${NC}"
            echo -e "  📝 Re-run specific test: ${BLUE}./\${test_file}${NC}"
            echo -e "  🔍 Verbose mode: ${BLUE}./run_tests.sh -v${NC}"
            echo -e "  ⚙️  Check dependencies: tmux, jq, timeout, terminal-notifier"
            echo -e "  🧹 Clean environment: Remove stale tmux sessions, temp files"
            echo -e "  📊 Test logs location: /tmp/\${test_name}*.log (if applicable)"
        fi
        
        # Report overall test results summary
        echo -e "\n${BLUE}=== Test Execution Summary ===${NC}"
        if [ "$bats_exit_code" -eq 0 ]; then
            echo -e "${GREEN}✓ BATS tests: PASSED${NC}"
        else
            echo -e "${RED}✗ BATS tests: FAILED${NC}"
            echo -e "  ${YELLOW}Run with --verbose-run flag for detailed BATS output${NC}"
        fi
        
        if [ "$shell_tests_exit_code" -eq 0 ]; then
            echo -e "${GREEN}✓ Shell script tests: PASSED${NC}"
        else
            echo -e "${RED}✗ Shell script tests: FAILED${NC}"
        fi
        
        # Return failure if either BATS tests or shell script tests failed
        if [ "$bats_exit_code" -ne 0 ] || [ "$shell_tests_exit_code" -ne 0 ]; then
            return 1
        fi
        
        return 0
    fi
}

# テスト結果の表示
show_results() {
    local exit_code=$1

    echo ""
    echo -e "${BLUE}=== Test Results ===${NC}"

    if [ "$exit_code" -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        echo ""
        echo "Troubleshooting tips:"
        echo "  - Check if all required tools are installed (tmux, jq, timeout)"
        echo "  - Ensure no conflicting tmux sessions are running"
        echo "  - Run with -v flag for verbose output"
        echo "  - Check individual test files for specific failures"
    fi

    return "$exit_code"
}

# メイン処理
main() {
    echo -e "${YELLOW}Preparing test environment...${NC}"

    # 事前クリーンアップ
    cleanup_before_test

    # テストの実行
    echo -e "${YELLOW}Starting tests...${NC}"
    echo ""

    if run_tests; then
        show_results 0
    else
        show_results 1
    fi
}

# トラップ設定（テスト終了時のクリーンアップ）
trap_cleanup() {
    echo -e "\n${YELLOW}Cleaning up after tests...${NC}"
    cleanup_before_test
}

trap trap_cleanup EXIT INT TERM

# メイン実行
main "$@"

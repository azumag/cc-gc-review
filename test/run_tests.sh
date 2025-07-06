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
        
        # Load test configuration from external JSON file
        local config_file="${TEST_DIR}/test-config.json"
        if [ ! -f "$config_file" ]; then
            echo -e "${RED}Error: Test configuration file not found: $config_file${NC}" >&2
            return 1
        fi
        
        # Extract test definitions from JSON config
        local shell_tests_json
        if ! shell_tests_json=$(jq -r '.shell_tests[] | "\(.file):\(.description):\(.timeout // 60):\(.category)"' "$config_file" 2>/dev/null); then
            echo -e "${RED}Error: Failed to parse test configuration${NC}" >&2
            return 1
        fi
        
        # Extract error patterns from config
        local critical_patterns warning_patterns error_patterns
        critical_patterns=$(jq -r '.error_patterns.critical | join("|")' "$config_file" 2>/dev/null || echo "FATAL|CRITICAL")
        error_patterns=$(jq -r '.error_patterns.errors | join("|")' "$config_file" 2>/dev/null || echo "Error:|✗|FAIL|Failed")
        warning_patterns=$(jq -r '.error_patterns.warnings | join("|")' "$config_file" 2>/dev/null || echo "WARN|Warning")
        
        # Extract output limits
        local max_error_lines max_error_indicators max_failed_cases
        max_error_lines=$(jq -r '.output_limits.max_error_lines // 10' "$config_file" 2>/dev/null)
        max_error_indicators=$(jq -r '.output_limits.max_error_indicators // 5' "$config_file" 2>/dev/null)
        max_failed_cases=$(jq -r '.output_limits.max_failed_cases // 3' "$config_file" 2>/dev/null)
        
        # Track test results with associative arrays for better maintainability
        declare -A test_results
        declare -A test_stdout_outputs
        declare -A test_stderr_outputs
        declare -A test_categories
        
        # Run each shell script test based on JSON configuration
        while IFS= read -r test_spec; do
            [ -z "$test_spec" ] && continue
            
            local test_file test_description test_timeout test_category
            IFS=':' read -r test_file test_description test_timeout test_category <<< "$test_spec"
            
            echo -e "\n${YELLOW}Running $test_description (timeout: ${test_timeout}s)...${NC}"
            
            # Create temporary files for stdout and stderr separation
            local stdout_file stderr_file
            stdout_file=$(mktemp)
            stderr_file=$(mktemp)
            
            # Run test with timeout and separated output streams
            local test_exit_code=0
            if command -v timeout >/dev/null 2>&1; then
                timeout "${test_timeout}s" ./"$test_file" >"$stdout_file" 2>"$stderr_file" || test_exit_code=$?
            else
                ./"$test_file" >"$stdout_file" 2>"$stderr_file" || test_exit_code=$?
            fi
            
            # Store results and outputs
            local stdout_content stderr_content
            stdout_content=$(cat "$stdout_file" 2>/dev/null)
            stderr_content=$(cat "$stderr_file" 2>/dev/null)
            
            if [ "$test_exit_code" -eq 0 ]; then
                echo -e "${GREEN}✓ $test_description passed${NC}"
                test_results["$test_file"]="PASSED"
            else
                echo -e "${RED}✗ $test_description failed (exit code: $test_exit_code)${NC}"
                test_results["$test_file"]="FAILED"
                shell_tests_exit_code=1
            fi
            
            test_stdout_outputs["$test_file"]="$stdout_content"
            test_stderr_outputs["$test_file"]="$stderr_content"
            test_categories["$test_file"]="$test_category"
            
            # Cleanup temporary files
            rm -f "$stdout_file" "$stderr_file"
            
        done <<< "$shell_tests_json"
        
        # Report detailed failure information if any tests failed
        if [ "$shell_tests_exit_code" -ne 0 ]; then
            echo -e "\n${RED}=== SHELL TEST FAILURE ANALYSIS ===${NC}"
            
            # Group failures by category
            declare -A category_failures
            for test_file in "${!test_results[@]}"; do
                if [ "${test_results[$test_file]}" = "FAILED" ]; then
                    local category="${test_categories[$test_file]}"
                    category_failures["$category"]+="$test_file "
                fi
            done
            
            # Report failures by category
            for category in "${!category_failures[@]}"; do
                echo -e "\n${BLUE}=== $category Test Failures ===${NC}"
                for test_file in ${category_failures[$category]}; do
                    echo -e "\n${RED}Failed Test: $test_file${NC}"
                    
                    local stdout_content="${test_stdout_outputs[$test_file]}"
                    local stderr_content="${test_stderr_outputs[$test_file]}"
                    
                    # Analyze stderr first (usually contains error information)
                    if [ -n "$stderr_content" ]; then
                        echo -e "${YELLOW}Error Output (stderr, last $max_error_lines lines):${NC}"
                        echo "$stderr_content" | tail -n "$max_error_lines" | sed 's/^/  🔥 /'
                        
                        # Look for critical patterns first
                        local critical_lines
                        if critical_lines=$(echo "$stderr_content" | grep -E "($critical_patterns)" | head -"$max_error_indicators"); then
                            echo -e "${RED}Critical Issues:${NC}"
                            echo "$critical_lines" | sed 's/^/  💥 /'
                        fi
                        
                        # Look for error patterns
                        local error_lines
                        if error_lines=$(echo "$stderr_content" | grep -E "($error_patterns)" | head -"$max_error_indicators"); then
                            echo -e "${YELLOW}Error Indicators:${NC}"
                            echo "$error_lines" | sed 's/^/  🔍 /'
                        fi
                    fi
                    
                    # Analyze stdout for test case failures
                    if [ -n "$stdout_content" ]; then
                        local failed_cases
                        if failed_cases=$(echo "$stdout_content" | grep -E "($error_patterns)" | head -"$max_failed_cases"); then
                            echo -e "${YELLOW}Failed Test Cases:${NC}"
                            echo "$failed_cases" | sed 's/^/  📋 /'
                        fi
                        
                        # Show warnings if any
                        local warning_lines
                        if warning_lines=$(echo "$stdout_content" | grep -E "($warning_patterns)" | head -3); then
                            echo -e "${YELLOW}Warnings:${NC}"
                            echo "$warning_lines" | sed 's/^/  ⚠️  /'
                        fi
                    fi
                    
                    echo -e "${BLUE}$(printf '%.0s-' {1..50})${NC}"
                done
            done
            
            echo -e "\n${YELLOW}Structured Debugging Guide:${NC}"
            echo -e "  📝 Re-run specific test: ${BLUE}./\${test_file}${NC}"
            echo -e "  🔍 Verbose mode: ${BLUE}./run_tests.sh -v${NC}"
            echo -e "  📊 Analyze category: Check all ${BLUE}\${category}${NC} tests"
            echo -e "  ⚙️  Check dependencies: $(jq -r '.shell_tests[].required_dependencies[]?' "$config_file" 2>/dev/null | sort -u | tr '\n' ' ')"
            echo -e "  🧹 Clean environment: Remove stale sessions, clear temp files"
            echo -e "  📋 Review config: ${BLUE}$config_file${NC}"
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

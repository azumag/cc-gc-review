#!/bin/bash

# run_tests.sh - テスト実行スクリプト

set -euo pipefail

# 色付き出力
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Common output helper functions
log_info() { echo -e "${BLUE}$*${NC}"; }
log_success() { echo -e "${GREEN}$*${NC}"; }
log_warning() { echo -e "${YELLOW}$*${NC}"; }
log_error() { echo -e "${RED}$*${NC}" >&2; }
log_header() { echo -e "${BLUE}=== $* ===${NC}"; }
log_step() { echo -e "\n${YELLOW}$*${NC}"; }

# スクリプトのディレクトリを取得
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$TEST_DIR"

# Global temporary file tracking for cleanup
declare -a TEMP_FILES=()

# Robust cleanup function
cleanup_temp_files() {
    local exit_code=$?
    if [ ${#TEMP_FILES[@]} -gt 0 ]; then
        log_warning "Cleaning up ${#TEMP_FILES[@]} temporary files..."
        for temp_file in "${TEMP_FILES[@]}"; do
            [ -f "$temp_file" ] && rm -f "$temp_file"
        done
        TEMP_FILES=()
    fi
    exit $exit_code
}

# Set trap for cleanup on script exit
trap cleanup_temp_files EXIT INT TERM

# Create tracked temporary file
create_temp_file() {
    local temp_file
    temp_file=$(mktemp)
    TEMP_FILES+=("$temp_file")
    echo "$temp_file"
}

# Validate essential dependencies
validate_dependencies() {
    local missing_deps=()
    local optional_deps=()
    local required_commands=("jq" "bash")
    local optional_commands=("timeout" "bats")
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    for cmd in "${optional_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            optional_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Please install missing commands before running tests"
        return 1
    fi
    
    if [ ${#optional_deps[@]} -gt 0 ]; then
        log_warning "Missing optional dependencies: ${optional_deps[*]}"
        log_warning "Some test features may be limited or unreliable"
    fi
    
    return 0
}

# JSON schema validation function
validate_json_config() {
    local config_file="$1"
    
    # Validate JSON is parseable
    if ! jq '.' "$config_file" >/dev/null 2>&1; then
        log_error "Invalid JSON in config file: $config_file"
        return 1
    fi
    
    # Basic structure validation
    if ! jq -e '.shell_tests | type == "array"' "$config_file" >/dev/null 2>&1; then
        log_error "Invalid config: 'shell_tests' must be an array"
        return 1
    fi
    
    if ! jq -e '.error_patterns | type == "object"' "$config_file" >/dev/null 2>&1; then
        log_error "Invalid config: 'error_patterns' must be an object"
        return 1
    fi
    
    # Validate error_patterns structure
    local required_patterns=("critical" "errors" "warnings")
    for pattern in "${required_patterns[@]}"; do
        if ! jq -e ".error_patterns.$pattern | type == \"array\"" "$config_file" >/dev/null 2>&1; then
            log_error "Invalid config: error_patterns.$pattern must be an array"
            return 1
        fi
    done
    
    # Validate each test has required fields and file exists
    local test_count
    test_count=$(jq -r '.shell_tests | length' "$config_file")
    for ((i=0; i<test_count; i++)); do
        if ! jq -e ".shell_tests[$i] | has(\"file\") and has(\"description\")" "$config_file" >/dev/null 2>&1; then
            log_error "Invalid config: Test $i missing required fields (file, description)"
            return 1
        fi
        
        local test_file
        test_file=$(jq -r ".shell_tests[$i].file" "$config_file")
        if [ ! -f "$test_file" ]; then
            log_warning "Test file does not exist: $test_file (will fail during execution)"
        fi
        
        # Validate timeout is a positive number
        local timeout_val
        timeout_val=$(jq -r ".shell_tests[$i].timeout // 60" "$config_file")
        if ! [[ "$timeout_val" =~ ^[0-9]+$ ]] || [ "$timeout_val" -le 0 ]; then
            log_error "Invalid config: Test $i timeout must be a positive integer"
            return 1
        fi
    done
    
    return 0
}

log_header "Shell Script Test Runner"
log_info "Test directory: $TEST_DIR"

# Validate dependencies first
if ! validate_dependencies; then
    exit 1
fi

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
        log_error "Unknown option: $1"
        show_usage
        exit 1
        ;;
    esac
done

# テスト前のクリーンアップ
cleanup_before_test() {
    log_step "Cleaning up test environment..."

    # 既存のテスト用tmuxセッションを終了
    tmux list-sessions 2>/dev/null | grep "test-claude" | cut -d: -f1 | xargs -I {} tmux kill-session -t {} 2>/dev/null || true

    # テスト用一時ファイルを削除
    rm -rf ./test-tmp-* 2>/dev/null || true
    rm -f /tmp/gemini-review* 2>/dev/null || true
    rm -f /tmp/gemini-prompt* 2>/dev/null || true
    rm -f /tmp/cc-gc-review-* 2>/dev/null || true

    # mktemp で作成された一時ディレクトリも削除
    find /tmp -maxdepth 1 -name "tmp.*" -type d -user "$(whoami)" -mtime +1 -exec rm -rf {} + 2>/dev/null || true

    log_success "✓ Cleanup completed"
}

# CI環境の検出と対応
setup_ci_environment() {
    if [ "${CI:-false}" = "true" ]; then
        log_warning "CI environment detected, applying CI-specific settings..."

        # CI環境でのtmuxの初期化
        export TMUX_TMPDIR=/tmp

        # CI環境での表示設定
        export TERM=xterm-256color

        # Batsヘルパーライブラリの自動セットアップ
        if [ ! -d "test_helper/bats-support" ] || [ ! -d "test_helper/bats-assert" ] || [ ! -d "test_helper/bats-file" ]; then
            log_warning "Setting up bats helper libraries for CI..."
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

        log_success "✓ CI environment setup completed"
    fi
}

# CI環境のセットアップ（早期実行）
setup_ci_environment

# Batsヘルパーライブラリのパスを設定（CI/ローカル両方で）
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export BATS_LIB_PATH="${SCRIPT_DIR}/test_helper/bats-support:${SCRIPT_DIR}/test_helper/bats-assert:${SCRIPT_DIR}/test_helper/bats-file:${BATS_LIB_PATH:-}"

# 必要なツールの確認
if ! command -v bats >/dev/null 2>&1; then
    log_error "bats is not installed"
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
            log_error "Test file not found: $TEST_FILE"
            exit 1
        fi
        log_step "Running specific test file: $TEST_FILE"
        if [ -n "$TEST_PATTERN" ]; then
            bats "$bats_options" --filter "$TEST_PATTERN" "$TEST_FILE"
        else
            bats "$bats_options" "$TEST_FILE"
        fi
    else
        log_step "Running all test files..."
        
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
            log_error "Test configuration file not found: $config_file"
            return 1
        fi
        
        # Validate JSON configuration structure
        if ! validate_json_config "$config_file"; then
            log_error "Configuration validation failed"
            return 1
        fi
        
        # Check test-specific dependencies
        local test_deps
        test_deps=$(jq -r '.shell_tests[].required_dependencies[]?' "$config_file" 2>/dev/null | sort -u)
        if [ -n "$test_deps" ]; then
            local missing_test_deps=()
            while IFS= read -r dep; do
                [ -z "$dep" ] && continue
                if ! command -v "$dep" >/dev/null 2>&1; then
                    missing_test_deps+=("$dep")
                fi
            done <<< "$test_deps"
            
            if [ ${#missing_test_deps[@]} -gt 0 ]; then
                log_warning "Missing test dependencies: ${missing_test_deps[*]}"
                log_warning "Some tests may fail or be skipped"
            fi
        fi
        
        # Extract test definitions from JSON config
        local shell_tests_json
        if ! shell_tests_json=$(jq -r '.shell_tests[] | "\(.file):\(.description):\(.timeout // 60):\(.category)"' "$config_file" 2>/dev/null); then
            log_error "Failed to parse test configuration"
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
        
        # Check Bash version for associative array support
        if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
            echo -e "${RED}Error: Bash 4.0+ required for associative arrays (current: $BASH_VERSION)${NC}" >&2
            echo -e "${YELLOW}Please upgrade Bash or run individual test scripts${NC}" >&2
            return 1
        fi
        
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
            
            log_step "\nRunning $test_description (timeout: ${test_timeout}s)..."
            
            # Create temporary files for stdout and stderr separation
            local stdout_file stderr_file
            stdout_file=$(create_temp_file)
            stderr_file=$(create_temp_file)
            
            # Run test with timeout and separated output streams
            local test_exit_code=0
            if command -v timeout >/dev/null 2>&1; then
                timeout "${test_timeout}s" ./"$test_file" >"$stdout_file" 2>"$stderr_file" || test_exit_code=$?
            else
                # For critical tests, fail if timeout is not available
                if [ "$test_timeout" -lt 30 ] && echo "$test_file" | grep -q "critical\|security\|core"; then
                    log_error "Critical test $test_file requires timeout command for reliability"
                    echo "Error: timeout command required for critical test" >"$stderr_file"
                    test_exit_code=1
                else
                    log_warning "Running $test_file without timeout (timeout command unavailable)"
                    ./"$test_file" >"$stdout_file" 2>"$stderr_file" || test_exit_code=$?
                fi
            fi
            
            # Store results and outputs
            local stdout_content stderr_content
            stdout_content=$(cat "$stdout_file" 2>/dev/null)
            stderr_content=$(cat "$stderr_file" 2>/dev/null)
            
            if [ "$test_exit_code" -eq 0 ]; then
                log_success "✓ $test_description passed"
                test_results["$test_file"]="PASSED"
            else
                log_error "✗ $test_description failed (exit code: $test_exit_code)"
                test_results["$test_file"]="FAILED"
                shell_tests_exit_code=1
            fi
            
            test_stdout_outputs["$test_file"]="$stdout_content"
            test_stderr_outputs["$test_file"]="$stderr_content"
            test_categories["$test_file"]="$test_category"
            
            # Note: Temporary files are automatically cleaned up by trap handler
            
        done <<< "$shell_tests_json"
        
        # Report detailed failure information if any tests failed
        if [ "$shell_tests_exit_code" -ne 0 ]; then
            log_header "\nSHELL TEST FAILURE ANALYSIS"
            
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
                log_header "\n$category Test Failures"
                for test_file in ${category_failures[$category]}; do
                    log_error "\nFailed Test: $test_file"
                    
                    local stdout_content="${test_stdout_outputs[$test_file]}"
                    local stderr_content="${test_stderr_outputs[$test_file]}"
                    
                    # Analyze stderr first (usually contains error information)
                    if [ -n "$stderr_content" ]; then
                        log_warning "Error Output (stderr, last $max_error_lines lines):"
                        echo "$stderr_content" | tail -n "$max_error_lines" | sed 's/^/  🔥 /'
                        
                        # Look for critical patterns first
                        local critical_lines
                        if critical_lines=$(echo "$stderr_content" | grep -E "($critical_patterns)" | head -"$max_error_indicators"); then
                            log_error "Critical Issues:"
                            echo "$critical_lines" | sed 's/^/  💥 /'
                        fi
                        
                        # Look for error patterns
                        local error_lines
                        if error_lines=$(echo "$stderr_content" | grep -E "($error_patterns)" | head -"$max_error_indicators"); then
                            log_warning "Error Indicators:"
                            echo "$error_lines" | sed 's/^/  🔍 /'
                        fi
                    fi
                    
                    # Analyze stdout for test case failures
                    if [ -n "$stdout_content" ]; then
                        local failed_cases
                        if failed_cases=$(echo "$stdout_content" | grep -E "($error_patterns)" | head -"$max_failed_cases"); then
                            log_warning "Failed Test Cases:"
                            echo "$failed_cases" | sed 's/^/  📋 /'
                        fi
                        
                        # Show warnings if any
                        local warning_lines
                        if warning_lines=$(echo "$stdout_content" | grep -E "($warning_patterns)" | head -3); then
                            log_warning "Warnings:"
                            echo "$warning_lines" | sed 's/^/  ⚠️  /'
                        fi
                    fi
                    
                    log_info "$(printf '%.0s-' {1..50})"
                done
            done
            
            log_warning "\nStructured Debugging Guide:"
            log_info "  📝 Re-run specific test: ./\${test_file}"
            log_info "  🔍 Verbose mode: ./run_tests.sh -v"
            log_info "  📊 Analyze category: Check all \${category} tests"
            log_info "  ⚙️  Check dependencies: $(jq -r '.shell_tests[].required_dependencies[]?' "$config_file" 2>/dev/null | sort -u | tr '\n' ' ')"
            log_info "  🧹 Clean environment: Remove stale sessions, clear temp files"
            log_info "  📋 Review config: $config_file"
        fi
        
        # Report overall test results summary
        log_header "\nTest Execution Summary"
        if [ "$bats_exit_code" -eq 0 ]; then
            log_success "✓ BATS tests: PASSED"
        else
            log_error "✗ BATS tests: FAILED"
            log_warning "  Run with --verbose-run flag for detailed BATS output"
        fi
        
        if [ "$shell_tests_exit_code" -eq 0 ]; then
            log_success "✓ Shell script tests: PASSED"
        else
            log_error "✗ Shell script tests: FAILED"
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
    log_header "Test Results"

    if [ "$exit_code" -eq 0 ]; then
        log_success "✓ All tests passed!"
    else
        log_error "✗ Some tests failed"
        echo ""
        log_info "Troubleshooting tips:"
        log_info "  - Check if all required tools are installed (tmux, jq, timeout)"
        log_info "  - Ensure no conflicting tmux sessions are running"
        log_info "  - Run with -v flag for verbose output"
        log_info "  - Check individual test files for specific failures"
    fi

    return "$exit_code"
}

# メイン処理
main() {
    log_step "Preparing test environment..."

    # 事前クリーンアップ
    cleanup_before_test

    # テストの実行
    log_step "Starting tests..."
    echo ""

    if run_tests; then
        show_results 0
    else
        show_results 1
    fi
}

# トラップ設定（テスト終了時のクリーンアップ）
trap_cleanup() {
    log_step "\nCleaning up after tests..."
    cleanup_before_test
}

trap trap_cleanup EXIT INT TERM

# メイン実行
main "$@"

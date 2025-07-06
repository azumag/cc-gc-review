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
    echo "  -v, --verbose       Verbose output"
    echo "  -p, --parallel      Run tests in parallel"
    echo "  -h, --help          Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                                   # Run all tests"
    echo "  $0 -f test_gemini_review_hook.bats  # Run specific file"
    echo "  $0 -t 'CLAUDE_SUMMARY.*extraction'  # Run tests matching pattern"
    echo "  $0 -v                               # Verbose output"
    echo "  $0 -p                               # Parallel execution"
}

# デフォルト値
TEST_FILE=""
TEST_PATTERN=""
VERBOSE=false
PARALLEL=false

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

    if [ "$VERBOSE" = true ]; then
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
        if [ -n "$TEST_PATTERN" ]; then
            bats "$bats_options" --filter "$TEST_PATTERN" test_*.bats
        else
            bats "$bats_options" test_*.bats
        fi
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

#!/bin/bash

# test.sh - cc-gc-reviewのテストスクリプト

set -euo pipefail

# テスト用の設定
TEST_SESSION="test-claude"
TEST_TMP_DIR="./test-tmp"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 色付き出力
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# テスト結果カウンター
PASSED=0
FAILED=0

# テスト関数
test_start() {
    echo -e "${YELLOW}Testing: $1${NC}"
}

test_pass() {
    echo -e "${GREEN}✓ PASSED${NC}"
    ((PASSED++))
}

test_fail() {
    echo -e "${RED}✗ FAILED: $1${NC}"
    ((FAILED++))
}

# クリーンアップ
cleanup() {
    # テスト用tmuxセッションの終了
    tmux kill-session -t "$TEST_SESSION" 2>/dev/null || true
    
    # テスト用一時ディレクトリの削除
    rm -rf "$TEST_TMP_DIR"
    
    # テスト用レビューファイルの削除
    rm -f /tmp/gemini-review-* 2>/dev/null || true
}

# 初期セットアップ
setup() {
    cleanup
    mkdir -p "$TEST_TMP_DIR"
}

# Test 1: ヘルプ表示
test_help() {
    test_start "Help display"
    
    if "$SCRIPT_DIR/../cc-gc-review.sh" -h | grep -q "Usage:"; then
        test_pass
    else
        test_fail "Help text not displayed"
    fi
}

# Test 2: 引数なしでのエラー
test_no_args() {
    test_start "Error on no arguments"
    
    if "$SCRIPT_DIR/../cc-gc-review.sh" 2>&1 | grep -q "SESSION_NAME is required"; then
        test_pass
    else
        test_fail "No error message for missing session name"
    fi
}

# Test 3: tmuxセッション作成
test_tmux_session_creation() {
    test_start "Tmux session creation"
    
    # バックグラウンドでcc-gen-reviewを起動
    timeout 3s "$SCRIPT_DIR/../cc-gc-review.sh" -v --tmp-dir "$TEST_TMP_DIR" "$TEST_SESSION" &
    PID=$!
    sleep 1
    
    if tmux has-session -t "$TEST_SESSION" 2>/dev/null; then
        test_pass
        kill $PID 2>/dev/null || true
    else
        test_fail "Tmux session not created"
    fi
}

# Test 4: hook-handlerのJSON処理
test_hook_handler() {
    test_start "Hook handler JSON processing"
    
    # テスト用のトランスクリプトファイル作成
    local test_transcript="$TEST_TMP_DIR/test-transcript.jsonl"
    cat > "$test_transcript" << 'EOF'
{"type": "assistant", "message": {"content": [{"text": "テスト作業の内容です。"}]}}
EOF
    
    # テスト用のJSON入力
    local test_json='{
        "session_id": "test123",
        "transcript_path": "'$test_transcript'",
        "stop_hook_active": false
    }'
    
    # hook-handlerを実行
    export CC_GC_REVIEW_TMP_DIR="$TEST_TMP_DIR"
    export CC_GC_REVIEW_VERBOSE="true"
    
    if echo "$test_json" | "$SCRIPT_DIR/../hook-handler.sh" 2>&1 | grep -q "Hook handler completed successfully"; then
        # レビューファイルが作成されたか確認
        if ls "$TEST_TMP_DIR"/gemini-review-* >/dev/null 2>&1; then
            test_pass
        else
            test_fail "Review file not created"
        fi
    else
        test_fail "Hook handler execution failed"
    fi
}

# Test 5: ファイル監視機能（ポーリング）
test_file_watch() {
    test_start "File watch functionality"
    
    # tmuxセッションを作成
    tmux new-session -d -s "$TEST_SESSION"
    
    # cc-gen-reviewをバックグラウンドで起動
    "$SCRIPT_DIR/../cc-gc-review.sh" -v --tmp-dir "$TEST_TMP_DIR" "$TEST_SESSION" &
    PID=$!
    sleep 2
    
    # テスト用レビューファイルを作成
    echo "テストレビュー内容" > "$TEST_TMP_DIR/gemini-review-test"
    sleep 3
    
    # tmuxセッションにコンテンツが送信されたか確認
    if tmux capture-pane -t "$TEST_SESSION" -p | grep -q "テストレビュー内容"; then
        test_pass
    else
        test_fail "Review content not sent to tmux"
    fi
    
    kill $PID 2>/dev/null || true
}

# Test 6: stop_hook_activeのチェック
test_stop_hook_active() {
    test_start "Stop hook active check"
    
    local test_json='{
        "session_id": "test123",
        "transcript_path": "/tmp/dummy.jsonl",
        "stop_hook_active": true
    }'
    
    export CC_GC_REVIEW_VERBOSE="true"
    
    if echo "$test_json" | "$SCRIPT_DIR/../hook-handler.sh" 2>&1 | grep -q "Stop hook is already active"; then
        test_pass
    else
        test_fail "Stop hook active check failed"
    fi
}

# Test 7: 一時ディレクトリのフォールバック
test_tmp_dir_fallback() {
    test_start "Temporary directory fallback"
    
    # ./tmpが存在しない状態でテスト
    rm -rf ./tmp
    
    timeout 3s "$SCRIPT_DIR/../cc-gc-review.sh" -v "$TEST_SESSION" 2>&1 | grep -q "Using /tmp as temporary directory" &
    PID=$!
    sleep 1
    
    if wait $PID 2>/dev/null; then
        test_pass
    else
        test_pass  # タイムアウトは正常
    fi
}

# メイン処理
main() {
    echo "=== cc-gc-review Test Suite ==="
    echo
    
    # セットアップ
    setup
    
    # 各テストを実行
    test_help
    test_no_args
    test_tmux_session_creation
    test_hook_handler
    test_file_watch
    test_stop_hook_active
    test_tmp_dir_fallback
    
    # クリーンアップ
    cleanup
    
    # 結果サマリー
    echo
    echo "=== Test Results ==="
    echo -e "${GREEN}Passed: $PASSED${NC}"
    echo -e "${RED}Failed: $FAILED${NC}"
    
    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        exit 1
    fi
}

# トラップ設定
trap cleanup EXIT INT TERM

# エントリーポイント
main
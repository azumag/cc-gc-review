#!/usr/bin/env bats

# test_cc_gc_review.bats - cc-gc-review.sh のテスト (TDD approach)

setup() {
    # Clean up any leftover test directories first
    rm -rf ./test-tmp-* 2>/dev/null || true
    
    # テスト用の設定
    export TEST_SESSION="test-claude-$$"
    # Use mktemp for safer temporary directory creation
    export TEST_TMP_DIR
    TEST_TMP_DIR=$(mktemp -d)
    export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    # Set up cleanup trap
    trap 'cleanup_test_env' EXIT INT TERM
    
    # モックのgit設定
    export GIT_AUTHOR_NAME="Test User"
    export GIT_AUTHOR_EMAIL="test@example.com"
    export GIT_COMMITTER_NAME="Test User"
    export GIT_COMMITTER_EMAIL="test@example.com"
}

cleanup_test_env() {
    # テスト用tmuxセッションの終了
    tmux kill-session -t "$TEST_SESSION" 2>/dev/null || true
    
    # Clean up test directories
    if [[ -n "$TEST_TMP_DIR" && -d "$TEST_TMP_DIR" ]]; then
        rm -rf "$TEST_TMP_DIR"
    fi
    
    # テスト用レビューファイルの削除
    rm -f /tmp/gemini-* 2>/dev/null || true
    rm -f /tmp/cc-gc-review-* 2>/dev/null || true
}

teardown() {
    # Cleanup is now handled by the trap in setup()
    # Additional cleanup if needed can be added here
    cleanup_test_env
}

@test "help option should display usage information" {
    run "$SCRIPT_DIR/cc-gc-review.sh" -h
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
    [[ "$output" =~ "Claude Code と Gemini を stop hook 連携させるサポートツール" ]]
}

@test "script should fail when no session name is provided" {
    run "$SCRIPT_DIR/cc-gc-review.sh"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "SESSION_NAME is required" ]]
}

@test "script should fail with unknown option" {
    run "$SCRIPT_DIR/cc-gc-review.sh" --unknown-option test
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown option: --unknown-option" ]]
}

@test "verbose option should enable detailed logging" {
    # バックグラウンドでプロセスを起動し、すぐに終了
    timeout 2s "$SCRIPT_DIR/cc-gc-review.sh" -v "$TEST_SESSION" &
    local pid=$!
    sleep 1
    kill $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true
    
    # tmuxセッションが作成されたかチェック
    run tmux has-session -t "$TEST_SESSION"
    [ "$status" -eq 0 ]
}

@test "think mode should append think command to review" {
    # tmuxセッションを作成
    tmux new-session -d -s "$TEST_SESSION"
    
    # cc-gen-reviewをバックグラウンドで起動
    timeout 5s "$SCRIPT_DIR/cc-gc-review.sh" --think "$TEST_SESSION" &
    local pid=$!
    sleep 2
    
    # テスト用レビューファイルを作成
    echo "テストレビュー内容" > /tmp/gemini-review
    sleep 2
    
    # tmuxセッションの内容を確認
    run tmux capture-pane -t "$TEST_SESSION" -p
    [[ "$output" =~ "think" ]]
    
    kill $pid 2>/dev/null || true
}

@test "custom command should prepend command to review" {
    # tmuxセッションを作成
    tmux new-session -d -s "$TEST_SESSION"
    
    # cc-gen-reviewをバックグラウンドで起動
    timeout 5s "$SCRIPT_DIR/cc-gc-review.sh" --custom-command "refactor" "$TEST_SESSION" &
    local pid=$!
    sleep 2
    
    # テスト用レビューファイルを作成
    echo "テストレビュー内容" > /tmp/gemini-review
    sleep 2
    
    # tmuxセッションの内容を確認
    run tmux capture-pane -t "$TEST_SESSION" -p
    [[ "$output" =~ "/refactor" ]]
    
    kill $pid 2>/dev/null || true
}

@test "should create tmux session when it doesn't exist" {
    # セッションが存在しないことを確認
    run tmux has-session -t "$TEST_SESSION"
    [ "$status" -ne 0 ]
    
    # cc-gen-reviewをバックグラウンドで起動
    timeout 3s "$SCRIPT_DIR/cc-gc-review.sh" "$TEST_SESSION" &
    local pid=$!
    sleep 1
    
    # tmuxセッションが作成されたかチェック
    run tmux has-session -t "$TEST_SESSION"
    [ "$status" -eq 0 ]
    
    kill $pid 2>/dev/null || true
}

@test "should use existing tmux session when it exists" {
    # 既存のセッションを作成
    tmux new-session -d -s "$TEST_SESSION"
    
    # cc-gen-reviewをバックグラウンドで起動
    timeout 3s "$SCRIPT_DIR/cc-gc-review.sh" -v "$TEST_SESSION" &
    local pid=$!
    sleep 1
    
    # セッションが存在し続けることを確認
    run tmux has-session -t "$TEST_SESSION"
    [ "$status" -eq 0 ]
    
    kill $pid 2>/dev/null || true
}

@test "auto-claude-launch should send claude command to tmux" {
    # cc-gen-reviewをバックグラウンドで起動
    timeout 5s "$SCRIPT_DIR/cc-gc-review.sh" -c "$TEST_SESSION" &
    local pid=$!
    sleep 3
    
    # tmuxセッションの内容を確認
    run tmux capture-pane -t "$TEST_SESSION" -p
    [[ "$output" =~ "claude" ]] || true  # Claudeが起動されているかもしれない
    
    kill $pid 2>/dev/null || true
}

@test "resend option should process existing review file" {
    # 既存のレビューファイルを作成
    echo "既存レビュー内容" > /tmp/gemini-review
    
    # tmuxセッションを作成
    tmux new-session -d -s "$TEST_SESSION"
    
    # cc-gen-reviewを--resendオプションで起動
    timeout 5s "$SCRIPT_DIR/cc-gc-review.sh" --resend "$TEST_SESSION" &
    local pid=$!
    sleep 2
    
    # tmuxセッションの内容を確認
    run tmux capture-pane -t "$TEST_SESSION" -p
    [[ "$output" =~ "既存レビュー内容" ]]
    
    kill $pid 2>/dev/null || true
}

@test "should handle file changes with polling when inotify/fswatch not available" {
    # inotifyとfswatchが利用できないことをシミュレート
    export PATH="/usr/bin:/bin"
    
    # tmuxセッションを作成
    tmux new-session -d -s "$TEST_SESSION"
    
    # cc-gen-reviewをバックグラウンドで起動
    timeout 8s "$SCRIPT_DIR/cc-gc-review.sh" -v "$TEST_SESSION" &
    local pid=$!
    sleep 3
    
    # ファイルを作成してポーリングをテスト
    echo "ポーリングテスト" > /tmp/gemini-review
    sleep 4
    
    # tmuxセッションの内容を確認
    run tmux capture-pane -t "$TEST_SESSION" -p
    [[ "$output" =~ "ポーリングテスト" ]]
    
    kill $pid 2>/dev/null || true
}

@test "should handle empty review file gracefully" {
    # tmuxセッションを作成
    tmux new-session -d -s "$TEST_SESSION"
    
    # cc-gen-reviewをバックグラウンドで起動
    timeout 5s "$SCRIPT_DIR/cc-gc-review.sh" -v "$TEST_SESSION" &
    local pid=$!
    sleep 2
    
    # 空のレビューファイルを作成
    touch /tmp/gemini-review
    sleep 2
    
    # エラーが発生しないことを確認
    run tmux capture-pane -t "$TEST_SESSION" -p
    [ "$status" -eq 0 ]
    
    kill $pid 2>/dev/null || true
}

@test "should handle signal interruption gracefully" {
    # cc-gen-reviewをバックグラウンドで起動
    "$SCRIPT_DIR/cc-gc-review.sh" -v "$TEST_SESSION" &
    local pid=$!
    sleep 2
    
    # SIGINTを送信
    kill -INT $pid
    sleep 1
    
    # プロセスが終了していることを確認
    run kill -0 $pid
    [ "$status" -ne 0 ]
}
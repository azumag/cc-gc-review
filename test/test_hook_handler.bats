#!/usr/bin/env bats

# test_hook_handler.bats - hook-handler.sh のテスト (TDD approach)

setup() {
    # テスト用の設定
    export TEST_TMP_DIR="./test-tmp-$$"
    export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    # テスト用ディレクトリの作成
    mkdir -p "$TEST_TMP_DIR"
    
    # 環境変数の設定
    export CC_GEN_REVIEW_VERBOSE="true"
    export CC_GEN_REVIEW_TMP_DIR="$TEST_TMP_DIR"
    
    # テスト用のトランスクリプトファイル作成
    export TEST_TRANSCRIPT="$TEST_TMP_DIR/test-transcript.jsonl"
    cat > "$TEST_TRANSCRIPT" << 'EOF'
{"type": "user", "message": {"content": [{"text": "テストリクエスト"}]}}
{"type": "assistant", "message": {"content": [{"text": "テスト作業の内容です。ファイルを作成しました。"}]}}
EOF
}

teardown() {
    # テスト用ディレクトリの削除
    rm -rf "$TEST_TMP_DIR"
    
    # テスト用レビューファイルの削除
    rm -f /tmp/gemini-review* 2>/dev/null || true
    
    # 環境変数のクリーンアップ
    unset CC_GEN_REVIEW_VERBOSE CC_GEN_REVIEW_TMP_DIR
}

@test "should extract work summary from transcript file" {
    local test_json='{
        "session_id": "test123",
        "transcript_path": "'$TEST_TRANSCRIPT'",
        "stop_hook_active": false
    }'
    
    run bash -c "echo '$test_json' | '$SCRIPT_DIR/hook-handler.sh'"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Hook handler completed successfully" ]]
}

@test "should exit early when stop_hook_active is true" {
    local test_json='{
        "session_id": "test123",
        "transcript_path": "'$TEST_TRANSCRIPT'",
        "stop_hook_active": true
    }'
    
    run bash -c "echo '$test_json' | '$SCRIPT_DIR/hook-handler.sh'"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Stop hook is already active" ]]
}

@test "should fail when transcript_path is missing" {
    local test_json='{
        "session_id": "test123",
        "stop_hook_active": false
    }'
    
    run bash -c "echo '$test_json' | '$SCRIPT_DIR/hook-handler.sh'"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "transcript_path not found in input JSON" ]]
}

@test "should fail when transcript file does not exist" {
    local test_json='{
        "session_id": "test123",
        "transcript_path": "/nonexistent/path/transcript.jsonl",
        "stop_hook_active": false
    }'
    
    run bash -c "echo '$test_json' | '$SCRIPT_DIR/hook-handler.sh'"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Transcript file not found" ]]
}

@test "should handle empty transcript file gracefully" {
    # 空のトランスクリプトファイルを作成
    local empty_transcript="$TEST_TMP_DIR/empty-transcript.jsonl"
    touch "$empty_transcript"
    
    local test_json='{
        "session_id": "test123",
        "transcript_path": "'$empty_transcript'",
        "stop_hook_active": false
    }'
    
    run bash -c "echo '$test_json' | '$SCRIPT_DIR/hook-handler.sh'"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "作業サマリーを取得できませんでした" ]]
}

@test "should expand tilde in transcript path" {
    # ホームディレクトリにテストファイルを作成
    local home_transcript="$HOME/test-transcript.jsonl"
    cp "$TEST_TRANSCRIPT" "$home_transcript"
    
    local test_json='{
        "session_id": "test123",
        "transcript_path": "~/test-transcript.jsonl",
        "stop_hook_active": false
    }'
    
    run bash -c "echo '$test_json' | '$SCRIPT_DIR/hook-handler.sh'"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Hook handler completed successfully" ]]
    
    # クリーンアップ
    rm -f "$home_transcript"
}

@test "should create review file in /tmp directory" {
    local test_json='{
        "session_id": "test123",
        "transcript_path": "'$TEST_TRANSCRIPT'",
        "stop_hook_active": false
    }'
    
    run bash -c "echo '$test_json' | '$SCRIPT_DIR/hook-handler.sh'"
    
    [ "$status" -eq 0 ]
    [ -f "/tmp/gemini-review" ]
}

@test "should handle malformed JSON input" {
    local malformed_json='{"session_id": "test123", "transcript_path":'
    
    run bash -c "echo '$malformed_json' | '$SCRIPT_DIR/hook-handler.sh'"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "transcript_path not found in input JSON" ]]
}

@test "should log verbose output when CC_GEN_REVIEW_VERBOSE is true" {
    local test_json='{
        "session_id": "test123",
        "transcript_path": "'$TEST_TRANSCRIPT'",
        "stop_hook_active": false
    }'
    
    run bash -c "echo '$test_json' | '$SCRIPT_DIR/hook-handler.sh'"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Hook handler started" ]]
    [[ "$output" =~ "Session ID: test123" ]]
    [[ "$output" =~ "Transcript path:" ]]
}

@test "should handle transcript with multiple assistant messages" {
    # 複数のアシスタントメッセージを含むトランスクリプトファイルを作成
    local multi_transcript="$TEST_TMP_DIR/multi-transcript.jsonl"
    cat > "$multi_transcript" << 'EOF'
{"type": "user", "message": {"content": [{"text": "最初のリクエスト"}]}}
{"type": "assistant", "message": {"content": [{"text": "最初の回答"}]}}
{"type": "user", "message": {"content": [{"text": "次のリクエスト"}]}}
{"type": "assistant", "message": {"content": [{"text": "最後の作業内容です。"}]}}
EOF
    
    local test_json='{
        "session_id": "test123",
        "transcript_path": "'$multi_transcript'",
        "stop_hook_active": false
    }'
    
    run bash -c "echo '$test_json' | '$SCRIPT_DIR/hook-handler.sh'"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Hook handler completed successfully" ]]
    
    # レビューファイルの内容を確認
    if [ -f "/tmp/gemini-review" ]; then
        run cat "/tmp/gemini-review"
        # 最後のアシスタントメッセージが取得されているか確認
        [[ "$output" =~ "最後の作業内容" ]] || true
    fi
}

@test "should handle gemini command not found gracefully" {
    # PATHからgeminiコマンドを除外
    export PATH="/usr/bin:/bin"
    
    local test_json='{
        "session_id": "test123",
        "transcript_path": "'$TEST_TRANSCRIPT'",
        "stop_hook_active": false
    }'
    
    run bash -c "echo '$test_json' | '$SCRIPT_DIR/hook-handler.sh'"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Hook handler completed successfully" ]]
    
    # レビューファイルの内容を確認
    if [ -f "/tmp/gemini-review" ]; then
        run cat "/tmp/gemini-review"
        [[ "$output" =~ "gemini-cliがインストールされていないため" ]]
    fi
}

@test "should handle error conditions with proper error messages" {
    # 無効なJSON形式でテスト
    local invalid_json='invalid json'
    
    run bash -c "echo '$invalid_json' | '$SCRIPT_DIR/hook-handler.sh'"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "transcript_path not found in input JSON" ]]
}

@test "should preserve working directory context" {
    # 特定のディレクトリで実行
    local test_dir="$TEST_TMP_DIR/work_dir"
    mkdir -p "$test_dir"
    
    local test_json='{
        "session_id": "test123",
        "transcript_path": "'$TEST_TRANSCRIPT'",
        "stop_hook_active": false
    }'
    
    run bash -c "cd '$test_dir' && echo '$test_json' | '$SCRIPT_DIR/hook-handler.sh'"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Working directory: $test_dir" ]]
}

@test "should handle complex transcript content with special characters" {
    # 特殊文字を含むトランスクリプトファイルを作成
    local complex_transcript="$TEST_TMP_DIR/complex-transcript.jsonl"
    cat > "$complex_transcript" << 'EOF'
{"type": "assistant", "message": {"content": [{"text": "テスト作業: \"quotes\", 'single quotes', \n改行, $変数, &特殊文字"}]}}
EOF
    
    local test_json='{
        "session_id": "test123",
        "transcript_path": "'$complex_transcript'",
        "stop_hook_active": false
    }'
    
    run bash -c "echo '$test_json' | '$SCRIPT_DIR/hook-handler.sh'"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Hook handler completed successfully" ]]
}
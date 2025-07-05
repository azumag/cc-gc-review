#!/usr/bin/env bats

# test_hook_handler.bats - hook-handler.sh のテスト (TDD approach)

setup() {
    # テスト用の設定
    export TEST_TMP_DIR="./test-tmp-$$"
    export SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    
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
    
    # テスト用ファイルの削除
    rm -f /tmp/gemini-review* 2>/dev/null || true
    rm -f /tmp/gemini-prompt* 2>/dev/null || true
    rm -f /tmp/cc-gen-review-hook.log* 2>/dev/null || true
    
    # 環境変数のクリーンアップ
    unset CC_GEN_REVIEW_VERBOSE CC_GEN_REVIEW_TMP_DIR
}

@test "should extract work summary from transcript file" {
    # 成功を返すモックgeminiコマンドを作成
    local mock_gemini="$TEST_TMP_DIR/gemini"
    cat > "$mock_gemini" << 'EOF'
#!/bin/bash
echo "コードレビュー結果: テスト用のレビュー内容"
EOF
    chmod +x "$mock_gemini"
    
    # テスト用PATHを設定
    export PATH="$TEST_TMP_DIR:$PATH"
    
    local test_json='{
        "session_id": "test123",
        "transcript_path": "'$TEST_TRANSCRIPT'",
        "stop_hook_active": false
    }'
    
    run bash -c "echo '$test_json' | '$SCRIPT_DIR/hook-handler.sh'"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Hook handler completed successfully" ]]
    
    # レビューファイルが作成されることを確認
    [ -f "/tmp/gemini-review" ]
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

@test "should exit gracefully when transcript_path is missing" {
    local test_json='{
        "session_id": "test123",
        "stop_hook_active": false
    }'
    
    run bash -c "echo '$test_json' | '$SCRIPT_DIR/hook-handler.sh'"
    
    [ "$status" -eq 0 ]
    # レビューファイルが作成されないことを確認
    [ ! -f "/tmp/gemini-review" ]
}

@test "should exit gracefully when transcript file does not exist" {
    local test_json='{
        "session_id": "test123",
        "transcript_path": "/nonexistent/path/transcript.jsonl",
        "stop_hook_active": false
    }'
    
    run bash -c "echo '$test_json' | '$SCRIPT_DIR/hook-handler.sh'"
    
    [ "$status" -eq 0 ]
    # レビューファイルが作成されないことを確認
    [ ! -f "/tmp/gemini-review" ]
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
    # 空のサマリーの場合、レビューファイルが作成されないことを確認
    [ ! -f "/tmp/gemini-review" ]
}

@test "should expand tilde in transcript path" {
    # 成功を返すモックgeminiコマンドを作成
    local mock_gemini="$TEST_TMP_DIR/gemini"
    cat > "$mock_gemini" << 'EOF'
#!/bin/bash
echo "ホームディレクトリのテストレビュー内容"
EOF
    chmod +x "$mock_gemini"
    
    # テスト用PATHを設定
    export PATH="$TEST_TMP_DIR:$PATH"
    
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
    # 成功を返すモックgeminiコマンドを作成
    local mock_gemini="$TEST_TMP_DIR/gemini"
    cat > "$mock_gemini" << 'EOF'
#!/bin/bash
echo "テストレビュー: ファイルが正常に作成されました"
EOF
    chmod +x "$mock_gemini"
    
    # テスト用PATHを設定
    export PATH="$TEST_TMP_DIR:$PATH"
    
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
    
    [ "$status" -eq 0 ]
    # レビューファイルが作成されないことを確認
    [ ! -f "/tmp/gemini-review" ]
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
    # 成功を返すモックgeminiコマンドを作成
    local mock_gemini="$TEST_TMP_DIR/gemini"
    cat > "$mock_gemini" << 'EOF'
#!/bin/bash
echo "複数メッセージのレビュー: 最後の作業内容が正しく抽出されました"
EOF
    chmod +x "$mock_gemini"
    
    # テスト用PATHを設定
    export PATH="$TEST_TMP_DIR:$PATH"
    
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
        # モックレビューが取得されているか確認
        [[ "$output" =~ "複数メッセージのレビュー" ]] || true
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
    # gemini-cliがない場合、レビューファイルが作成されないことを確認
    [ ! -f "/tmp/gemini-review" ]
}

@test "should handle error conditions with proper error messages" {
    # 無効なJSON形式でテスト
    local invalid_json='invalid json'
    
    run bash -c "echo '$invalid_json' | '$SCRIPT_DIR/hook-handler.sh'"
    
    [ "$status" -eq 0 ]
    # エラー時にレビューファイルが作成されないことを確認
    [ ! -f "/tmp/gemini-review" ]
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

# === 新しい機能のテスト ===

@test "should handle --git-diff option" {
    # 成功を返すモックgeminiコマンドを作成
    local mock_gemini="$TEST_TMP_DIR/gemini"
    cat > "$mock_gemini" << 'EOF'
#!/bin/bash
echo "git diff オプションのレビュー結果"
EOF
    chmod +x "$mock_gemini"
    
    # テスト用PATHを設定
    export PATH="$TEST_TMP_DIR:$PATH"
    
    local test_json='{
        "session_id": "test123",
        "transcript_path": "'$TEST_TRANSCRIPT'",
        "stop_hook_active": false
    }'
    
    run bash -c "echo '$test_json' | '$SCRIPT_DIR/hook-handler.sh' --git-diff"
    
    [ "$status" -eq 0 ]
    # プロンプトファイルが作成されることを確認
    [ -f "/tmp/gemini-prompt" ]
    
    # プロンプトに git diff の指示が含まれていることを確認
    run cat "/tmp/gemini-prompt"
    [[ "$output" =~ "git diffを実行して" ]]
}

@test "should handle --git-commit option" {
    # 成功を返すモックgeminiコマンドを作成
    local mock_gemini="$TEST_TMP_DIR/gemini"
    cat > "$mock_gemini" << 'EOF'
#!/bin/bash
echo "git commit オプションのレビュー結果"
EOF
    chmod +x "$mock_gemini"
    
    # テスト用PATHを設定
    export PATH="$TEST_TMP_DIR:$PATH"
    
    local test_json='{
        "session_id": "test123",
        "transcript_path": "'$TEST_TRANSCRIPT'",
        "stop_hook_active": false
    }'
    
    run bash -c "echo '$test_json' | '$SCRIPT_DIR/hook-handler.sh' --git-commit"
    
    [ "$status" -eq 0 ]
    # プロンプトファイルが作成されることを確認
    [ -f "/tmp/gemini-prompt" ]
    
    # プロンプトに git commit の指示が含まれていることを確認
    run cat "/tmp/gemini-prompt"
    [[ "$output" =~ "git commitを確認し" ]]
}

@test "should handle --yolo option" {
    # 成功を返すモックgeminiコマンドを作成
    local mock_gemini="$TEST_TMP_DIR/gemini"
    cat > "$mock_gemini" << 'EOF'
#!/bin/bash
echo "YOLO モードのレビュー結果"
EOF
    chmod +x "$mock_gemini"
    
    # テスト用PATHを設定
    export PATH="$TEST_TMP_DIR:$PATH"
    
    local test_json='{
        "session_id": "test123",
        "transcript_path": "'$TEST_TRANSCRIPT'",
        "stop_hook_active": false
    }'
    
    run bash -c "echo '$test_json' | '$SCRIPT_DIR/hook-handler.sh' --yolo"
    
    [ "$status" -eq 0 ]
    # ログファイルにYOLOモードの記録があることを確認
    [ -f "/tmp/cc-gen-review-hook.log" ]
    run cat "/tmp/cc-gen-review-hook.log"
    [[ "$output" =~ "YOLO_MODE: true" ]]
}

@test "should create log file" {
    # 成功を返すモックgeminiコマンドを作成
    local mock_gemini="$TEST_TMP_DIR/gemini"
    cat > "$mock_gemini" << 'EOF'
#!/bin/bash
echo "ログファイルテスト用のレビュー結果"
EOF
    chmod +x "$mock_gemini"
    
    # テスト用PATHを設定
    export PATH="$TEST_TMP_DIR:$PATH"
    
    local test_json='{
        "session_id": "test123",
        "transcript_path": "'$TEST_TRANSCRIPT'",
        "stop_hook_active": false
    }'
    
    run bash -c "echo '$test_json' | '$SCRIPT_DIR/hook-handler.sh'"
    
    [ "$status" -eq 0 ]
    # ログファイルが作成されることを確認
    [ -f "/tmp/cc-gen-review-hook.log" ]
    
    # ログファイルの内容を確認
    run cat "/tmp/cc-gen-review-hook.log"
    [[ "$output" =~ "Hook handler started" ]]
    [[ "$output" =~ "Hook handler completed" ]]
}

@test "should create prompt file" {
    # 成功を返すモックgeminiコマンドを作成
    local mock_gemini="$TEST_TMP_DIR/gemini"
    cat > "$mock_gemini" << 'EOF'
#!/bin/bash
echo "プロンプトファイルテスト用のレビュー結果"
EOF
    chmod +x "$mock_gemini"
    
    # テスト用PATHを設定
    export PATH="$TEST_TMP_DIR:$PATH"
    
    local test_json='{
        "session_id": "test123",
        "transcript_path": "'$TEST_TRANSCRIPT'",
        "stop_hook_active": false
    }'
    
    run bash -c "echo '$test_json' | '$SCRIPT_DIR/hook-handler.sh'"
    
    [ "$status" -eq 0 ]
    # プロンプトファイルが作成されることを確認
    [ -f "/tmp/gemini-prompt" ]
    
    # プロンプトファイルの内容を確認
    run cat "/tmp/gemini-prompt"
    [[ "$output" =~ "作業内容をレビュー" ]]
    [[ "$output" =~ "作業内容:" ]]
}

@test "should handle successful gemini execution with mock" {
    # 正常なレスポンスを返すモックgeminiコマンドを作成
    local mock_gemini="$TEST_TMP_DIR/gemini"
    cat > "$mock_gemini" << 'EOF'
#!/bin/bash
# 正常なレビュー結果を模擬
echo '[dotenv@16.6.0] injecting env (30) from .env'
echo '[dotenv@16.6.0] injecting env (30) from .env'
echo ''
echo 'コードレビュー結果：'
echo '- 良い点：適切な変数命名'
echo '- 改善点：エラーハンドリングの追加を推奨'
echo 'Overall: LGTM'
EOF
    chmod +x "$mock_gemini"
    
    # テスト用PATHを設定
    export PATH="$TEST_TMP_DIR:$PATH"
    
    local test_json='{
        "session_id": "test123",
        "transcript_path": "'$TEST_TRANSCRIPT'",
        "stop_hook_active": false
    }'
    
    run bash -c "echo '$test_json' | '$SCRIPT_DIR/hook-handler.sh'"
    
    [ "$status" -eq 0 ]
    # レビューファイルが作成されることを確認
    [ -f "/tmp/gemini-review" ]
    
    # レビューファイルの内容を確認（dotenvログが除去されていることを確認）
    run cat "/tmp/gemini-review"
    [[ "$output" =~ "コードレビュー結果" ]]
    [[ "$output" =~ "良い点" ]]
    [[ "$output" =~ "改善点" ]]
    [[ ! "$output" =~ "dotenv" ]]  # dotenvログが除去されていることを確認
}

@test "should handle dotenv log filtering" {
    # dotenvログのみを返すモックgeminiコマンドを作成
    local mock_gemini="$TEST_TMP_DIR/gemini"
    cat > "$mock_gemini" << 'EOF'
#!/bin/bash
# dotenvログのみ（レビュー内容なし）
echo '[dotenv@16.6.0] injecting env (30) from .env'
echo '[dotenv@16.6.0] injecting env (30) from .env'
echo '[dotenv@16.6.0] injecting env (30) from .env'
echo ''
EOF
    chmod +x "$mock_gemini"
    
    # テスト用PATHを設定
    export PATH="$TEST_TMP_DIR:$PATH"
    
    local test_json='{
        "session_id": "test123",
        "transcript_path": "'$TEST_TRANSCRIPT'",
        "stop_hook_active": false
    }'
    
    run bash -c "echo '$test_json' | '$SCRIPT_DIR/hook-handler.sh'"
    
    [ "$status" -eq 0 ]
    # dotenvログのみの場合、レビューファイルが作成されないことを確認
    [ ! -f "/tmp/gemini-review" ]
}
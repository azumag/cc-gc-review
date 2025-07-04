#!/bin/bash

# hook-handler.sh - Claude Codeのstop hookから呼び出されるハンドラー

set -euo pipefail

# 設定
TMP_DIR="${CC_GEN_REVIEW_TMP_DIR:-./tmp}"
VERBOSE="${CC_GEN_REVIEW_VERBOSE:-false}"
REVIEW_FILE_PREFIX="gemini-review"

# ログ関数
log() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [hook-handler] $*" >&2
    fi
}

error() {
    echo "[ERROR] [hook-handler] $*" >&2
    exit 1
}

# 一時ディレクトリの準備
setup_tmp_dir() {
    if [[ ! -d "$TMP_DIR" ]]; then
        if [[ "$TMP_DIR" == "./tmp" ]] && [[ ! -d "./tmp" ]]; then
            TMP_DIR="/tmp"
        else
            mkdir -p "$TMP_DIR"
        fi
    fi
    log "Using temporary directory: $TMP_DIR"
}

# 作業サマリーの取得
get_work_summary() {
    local transcript_path="$1"
    
    if [[ ! -f "$transcript_path" ]]; then
        error "Transcript file not found: $transcript_path"
    fi
    
    # 最後のassistantメッセージの内容を取得
    local summary=$(jq -r 'select(.type == "assistant")' "$transcript_path" | \
                   jq -sr '.[-1].message.content[-1].text' 2>/dev/null || echo "")
    
    if [[ -z "$summary" ]]; then
        log "Warning: Could not extract work summary from transcript"
        summary="作業サマリーを取得できませんでした。"
    fi
    
    echo "$summary"
}

# Geminiでレビューを実行
run_gemini_review() {
    local summary="$1"
    local output_file="$2"
    
    log "Running Gemini review..."
    
    # Geminiプロンプトの作成
    local prompt="以下の作業内容をレビューして、改善点や注意点があれば日本語で簡潔に指摘してください。良い点も含めてフィードバックをお願いします。

作業内容:
$summary

レビュー結果:"
    
    # gemini-cliを使用してレビューを実行
    if command -v gemini >/dev/null 2>&1; then
        # gemini-cliがインストールされている場合
        local review_result=$(echo "$prompt" | gemini -p 2>/dev/null || echo "Geminiレビューの実行に失敗しました。")
    else
        # gemini-cliがない場合は代替処理
        log "Warning: gemini command not found, using placeholder review"
        local review_result="[自動レビュー] gemini-cliがインストールされていないため、レビューを実行できませんでした。"
    fi
    
    # レビュー結果をファイルに書き込み
    echo "$review_result" > "$output_file"
    log "Review result written to: $output_file"
}

# メイン処理
main() {
    log "Hook handler started"
    
    # 標準入力からJSONを読み取る
    local input=$(cat)
    log "Received input: $input"
    
    # JSONパース
    local session_id=$(echo "$input" | jq -r '.session_id' 2>/dev/null || echo "")
    local transcript_path=$(echo "$input" | jq -r '.transcript_path' 2>/dev/null || echo "")
    local stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active' 2>/dev/null || echo "false")
    
    # 必須パラメータのチェック
    if [[ -z "$transcript_path" ]]; then
        error "transcript_path not found in input JSON"
    fi
    
    # パスの展開（~を$HOMEに変換）
    transcript_path="${transcript_path/#\~/$HOME}"
    
    log "Session ID: $session_id"
    log "Transcript path: $transcript_path"
    log "Stop hook active: $stop_hook_active"
    
    # stop_hook_activeがtrueの場合は無限ループを防ぐために終了
    if [[ "$stop_hook_active" == "true" ]]; then
        log "Stop hook is already active, exiting to prevent infinite loop"
        exit 0
    fi
    
    # 一時ディレクトリのセットアップ
    setup_tmp_dir
    
    # 作業サマリーの取得
    local work_summary=$(get_work_summary "$transcript_path")
    log "Work summary extracted (${#work_summary} characters)"
    
    # レビューファイル名の生成（単純化）
    local review_file="$TMP_DIR/gemini-review"
    
    # Geminiレビューの実行
    run_gemini_review "$work_summary" "$review_file"
    
    log "Hook handler completed successfully"
}

# エラーハンドリング
trap 'error "Hook handler failed with error on line $LINENO"' ERR

# エントリーポイント
main
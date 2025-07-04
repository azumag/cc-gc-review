#!/bin/bash

# cc-gen-review.sh - Claude Code と Gemini を stop hook 連携させるサポートツール

set -euo pipefail

# デフォルト値
SESSION_NAME=""
AUTO_CLAUDE_LAUNCH=false
TMP_DIR="/tmp"
THINK_MODE=false
VERBOSE=false
CUSTOM_COMMAND=""
RESEND_EXISTING=false
MAX_REVIEWS=4
INFINITE_REVIEW=false
REVIEW_COUNT_FILE="/tmp/cc-gen-review-count"

# ログ関数
log() {
    if [[ "$VERBOSE" == true ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
    fi
}

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

# ヘルプ表示
show_help() {
    cat << EOF
Usage: $0 [OPTIONS] SESSION_NAME

Claude Code と Gemini を stop hook 連携させるサポートツール

Options:
    -c, --auto-claude-launch    自動でClaudeを起動
    --think                     レビュー内容の後に'think'を追加
    --custom-command COMMAND    レビュー内容の先頭にカスタムコマンドを付加 (例: --custom-command "refactor" → /refactor)
    --resend                    起動時に既存のレビューファイルがあれば再送信
    --max-reviews N             レビュー数の上限を設定 (デフォルト: 4)
    --infinite-review           レビュー数の制限を無効化
    -v, --verbose               詳細ログを出力
    -h, --help                  このヘルプを表示

Example:
    $0 -c claude
    $0 --think --verbose claude-session
    $0 --custom-command "refactor" claude
    $0 --max-reviews 10 claude
    $0 --infinite-review claude
EOF
}

# 引数パース
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--auto-claude-launch)
                AUTO_CLAUDE_LAUNCH=true
                shift
                ;;
            --think)
                THINK_MODE=true
                shift
                ;;
            --custom-command)
                if [[ $# -lt 2 || -z "$2" ]]; then
                    error "--custom-command requires a command argument"
                fi
                CUSTOM_COMMAND="$2"
                shift 2
                ;;
            --resend)
                RESEND_EXISTING=true
                shift
                ;;
            --max-reviews)
                if [[ $# -lt 2 || -z "$2" ]]; then
                    error "--max-reviews requires a number argument"
                fi
                MAX_REVIEWS="$2"
                shift 2
                ;;
            --infinite-review)
                INFINITE_REVIEW=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                error "Unknown option: $1"
                ;;
            *)
                SESSION_NAME="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$SESSION_NAME" ]]; then
        error "SESSION_NAME is required"
    fi
}

# tmuxセッション管理
setup_tmux_session() {
    local session="$1"
    
    if ! tmux has-session -t "$session" 2>/dev/null; then
        log "Creating new tmux session: $session"
        tmux new-session -d -s "$session"
        
        if [[ "$AUTO_CLAUDE_LAUNCH" == true ]]; then
            log "Launching Claude in session: $session"
            tmux send-keys -t "$session" "claude" Enter
            sleep 2
        fi
    else
        log "Using existing tmux session: $session"
    fi
}



# レビュー結果をtmuxに送信
send_review_to_tmux() {
    local session="$1"
    local review_content="$2"
    
    # レビュー数制限チェック
    if [[ "$INFINITE_REVIEW" == false ]]; then
        local current_count=0
        if [[ -f "$REVIEW_COUNT_FILE" ]]; then
            current_count=$(cat "$REVIEW_COUNT_FILE" 2>/dev/null || echo "0")
        fi
        
        if [[ "$current_count" -ge "$MAX_REVIEWS" ]]; then
            echo "🚫 Review limit reached ($current_count/$MAX_REVIEWS). Stopping review loop."
            echo "   To continue, either:"
            echo "   1. Use --infinite-review option"
            echo "   2. Increase limit with --max-reviews N"
            echo "   3. Remove count file: rm $REVIEW_COUNT_FILE"
            return 1
        fi
        
        # レビューカウントを更新
        echo $((current_count + 1)) > "$REVIEW_COUNT_FILE"
        echo "📊 Review count: $((current_count + 1))/$MAX_REVIEWS"
    fi
    
    echo "📝 Review received (${#review_content} characters)"
    
    # thinkモードの場合はレビュー内容の末尾に追加
    if [[ "$THINK_MODE" == true ]]; then
        review_content="${review_content}

think"
        echo "🤔 Think mode enabled - appending 'think' command"
    fi
    
    # カスタムコマンドの場合はレビュー内容の先頭に追加
    if [[ -n "$CUSTOM_COMMAND" ]]; then
        review_content="/$CUSTOM_COMMAND

$review_content"
        echo "⚡ Custom command enabled - prepending '/$CUSTOM_COMMAND'"
    fi
    
    echo "📤 Sending review to tmux session: $session"
    log "Review content preview: ${review_content:0:100}..."
    
    # レビュー内容を送信
    tmux send-keys -t "$session" "$review_content" Enter
    
    # 5秒待ってから追加のEnterを送信
    sleep 5
    tmux send-keys -t "$session" "" Enter

    # 保険で再度送信
    sleep 5
    tmux send-keys -t "$session" "" Enter

    echo "✅ Review sent successfully"
    
    # ユーザーの続行確認を求める
    prompt_for_continuation
    local continuation_result=$?
    
    if [[ $continuation_result -eq 2 ]]; then
        # ユーザーが停止を選択した場合
        return 2
    fi
    
    return 0
}

# ユーザーの続行確認を求める（10秒タイムアウト付き）
prompt_for_continuation() {
    echo "続行します"
    echo "停止するには 'n' を入力してください (10秒後に自動で続行):"
    
    local input=""
    if read -t 10 -r input; then
        # ユーザーが何か入力した場合
        if [[ "$input" == "n" || "$input" == "N" ]]; then
            echo "❌ ユーザーによりレビューループを停止しました"
            return 2  # 停止を意味する特別な終了コード
        else
            echo "▶️  続行します"
            return 0  # 続行
        fi
    else
        # タイムアウトした場合（10秒経過）
        echo "▶️  タイムアウトしました。続行します"
        return 0  # 続行
    fi
}

# ファイル監視
watch_review_files() {
    local session="$1"
    local watch_file="/tmp/gemini-review"
    
    log "Starting file watch on: $watch_file"
    
    # 起動時の既存ファイルチェック
    if [[ -f "$watch_file" ]]; then
        if [[ "$RESEND_EXISTING" == true ]]; then
            log "Existing review file found, resending due to --resend option"
            local content=$(cat "$watch_file")
            if [[ -n "$content" ]]; then
                echo "🔄 Resending existing review file..."
                send_review_to_tmux "$session" "$content"
                local send_result=$?
                
                if [[ $send_result -eq 1 ]]; then
                    echo "⚠️  Review limit reached during resend. Exiting."
                    exit 1
                elif [[ $send_result -eq 2 ]]; then
                    echo "👋 Exiting by user request during resend."
                    exit 0
                fi
            fi
        else
            log "Existing review file found, ignoring (use --resend to send)"
            echo "⚠️  Existing review file found but ignored (use --resend to send)"
        fi
    fi
    
    # inotifyが使える場合はinotifywait、そうでなければfswatch、どちらもなければポーリング
    if command -v inotifywait >/dev/null 2>&1; then
        watch_with_inotify "$session" "$watch_file"
    elif command -v fswatch >/dev/null 2>&1; then
        watch_with_fswatch "$session" "$watch_file"
    else
        watch_with_polling "$session" "$watch_file"
    fi
}

# inotifywaitを使った監視
watch_with_inotify() {
    local session="$1"
    local watch_file="$2"
    
    log "Using inotifywait for file monitoring"
    
    while true; do
        inotifywait -e modify,create "/tmp" 2>/dev/null | while read -r dir event file; do
            if [[ "$file" == "gemini-review" ]]; then
                local filepath="$dir$file"
                log "Detected change in: $filepath"
                
                if [[ -f "$filepath" ]]; then
                    local content=$(cat "$filepath")
                    if [[ -n "$content" ]]; then
                        echo "🔔 New review detected via inotifywait!"
                        
                        # レビューカウントファイルをリセット（新しいファイル更新時）
                        if [[ -f "$REVIEW_COUNT_FILE" ]]; then
                            rm "$REVIEW_COUNT_FILE"
                            echo "🔄 Review count reset due to new file update"
                        fi
                        
                        send_review_to_tmux "$session" "$content"
                        local send_result=$?
                        
                        if [[ $send_result -eq 1 ]]; then
                            echo "⚠️  Review limit reached. Exiting watch mode."
                            exit 1
                        elif [[ $send_result -eq 2 ]]; then
                            echo "👋 Exiting watch mode by user request."
                            exit 0
                        fi
                    else
                        log "Warning: File exists but content is empty"
                    fi
                fi
            fi
        done
    done
}

# fswatchを使った監視
watch_with_fswatch() {
    local session="$1"
    local watch_file="$2"
    
    log "Using fswatch for file monitoring"
    
    fswatch -0 "$watch_file" | while IFS= read -r -d '' filepath; do
        log "Detected change in: $filepath"
        
        if [[ -f "$filepath" ]]; then
            local content=$(cat "$filepath")
            if [[ -n "$content" ]]; then
                echo "🔔 New review detected via fswatch!"
                
                # レビューカウントファイルをリセット（新しいファイル更新時）
                if [[ -f "$REVIEW_COUNT_FILE" ]]; then
                    rm "$REVIEW_COUNT_FILE"
                    echo "🔄 Review count reset due to new file update"
                fi
                
                send_review_to_tmux "$session" "$content"
                local send_result=$?
                
                if [[ $send_result -eq 1 ]]; then
                    echo "⚠️  Review limit reached. Exiting watch mode."
                    exit 1
                elif [[ $send_result -eq 2 ]]; then
                    echo "👋 Exiting watch mode by user request."
                    exit 0
                fi
            else
                log "Warning: File exists but content is empty"
            fi
        fi
    done
}

# ポーリングによる監視
watch_with_polling() {
    local session="$1"
    local watch_file="$2"
    local last_mtime="0"
    
    log "Using polling for file monitoring (checking every 2 seconds)"
    log "Watching file: $watch_file"
    
    # 初回の既存ファイルのmtimeを取得して初期化（送信を防ぐため）
    if [[ -f "$watch_file" ]]; then
        last_mtime=$(stat -c %Y "$watch_file" 2>/dev/null || stat -f %m "$watch_file" 2>/dev/null)
        log "Initial file mtime: $last_mtime (skipping initial send)"
    fi
    
    while true; do
        if [[ -f "$watch_file" ]]; then
            local current_mtime=$(stat -c %Y "$watch_file" 2>/dev/null || stat -f %m "$watch_file" 2>/dev/null)
            
            if [[ "$current_mtime" != "$last_mtime" ]]; then
                log "Detected file change: $watch_file (mtime: $current_mtime)"
                last_mtime="$current_mtime"
                
                local content=$(cat "$watch_file")
                if [[ -n "$content" ]]; then
                    echo "🔔 New review detected via polling!"
                    log "Sending review content (${#content} chars) to session: $session"
                    
                    # レビューカウントファイルをリセット（新しいファイル更新時）
                    if [[ -f "$REVIEW_COUNT_FILE" ]]; then
                        rm "$REVIEW_COUNT_FILE"
                        echo "🔄 Review count reset due to new file update"
                    fi
                    
                    send_review_to_tmux "$session" "$content"
                    local send_result=$?
                    
                    if [[ $send_result -eq 1 ]]; then
                        echo "⚠️  Review limit reached. Exiting watch mode."
                        exit 1
                    elif [[ $send_result -eq 2 ]]; then
                        echo "👋 Exiting watch mode by user request."
                        exit 0
                    fi
                else
                    log "Warning: File exists but content is empty"
                fi
            fi
        fi
        sleep 2
    done
}

# シグナルハンドラー
cleanup() {
    log "Shutting down cc-gen-review..."
    exit 0
}

trap cleanup INT TERM

# メイン処理
main() {
    parse_args "$@"
    
    echo "=== cc-gen-review starting ==="
    echo "Session name: $SESSION_NAME"
    echo "Review file: $TMP_DIR/gemini-review"
    echo "Think mode: $THINK_MODE"
    echo "Auto-launch Claude: $AUTO_CLAUDE_LAUNCH"
    echo "Resend existing: $RESEND_EXISTING"
    if [[ -n "$CUSTOM_COMMAND" ]]; then
        echo "Custom command: /$CUSTOM_COMMAND"
    fi
    if [[ "$INFINITE_REVIEW" == true ]]; then
        echo "Review limit: unlimited"
    else
        echo "Review limit: $MAX_REVIEWS"
    fi
    echo "============================="
    
    log "Starting cc-gen-review with session: $SESSION_NAME"
    
    # tmuxセッションのセットアップ
    setup_tmux_session "$SESSION_NAME"
    
    echo ""
    echo "✓ tmux session '$SESSION_NAME' is ready"
    echo "✓ Watching for review file: $TMP_DIR/gemini-review"
    echo ""
    echo "To attach to the session, run:"
    echo "  tmux attach-session -t $SESSION_NAME"
    echo ""
    echo "Press Ctrl+C to stop watching..."
    echo ""
    
    log "Session created. You can attach with: tmux attach-session -t $SESSION_NAME"
    
    # ファイル監視開始
    watch_review_files "$SESSION_NAME"
}

# エントリーポイント
main "$@"
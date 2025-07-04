#!/bin/bash

# cc-gen-review.sh - Claude Code と Gemini を stop hook 連携させるサポートツール

set -euo pipefail

# デフォルト値
SESSION_NAME=""
AUTO_CLAUDE_LAUNCH=false
TMP_DIR="./tmp"
THINK_MODE=false
VERBOSE=false

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
    -c, --auto-claude-launch 自動でClaudeを起動
    -t, --tmp-dir DIR        一時ファイル領域を指定 (default: ./tmp)
    --think                  レビュー内容の後に'think'を追加
    -v, --verbose            詳細ログを出力
    -h, --help               このヘルプを表示

Example:
    $0 -c claude
    $0 --tmp-dir /tmp/reviews claude-session
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
            -t|--tmp-dir)
                TMP_DIR="$2"
                shift 2
                ;;
            --think)
                THINK_MODE=true
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


# 一時ディレクトリのセットアップ
setup_tmp_dir() {
    if [[ ! -d "$TMP_DIR" ]]; then
        if [[ "$TMP_DIR" == "./tmp" ]] && [[ ! -d "./tmp" ]]; then
            TMP_DIR="/tmp"
            log "Using /tmp as temporary directory"
        else
            mkdir -p "$TMP_DIR"
            log "Created temporary directory: $TMP_DIR"
        fi
    fi
}

# レビュー結果をtmuxに送信
send_review_to_tmux() {
    local session="$1"
    local review_content="$2"
    
    log "Sending review to tmux session: $session"
    
    # レビュー内容を送信
    tmux send-keys -t "$session" "$review_content" Enter
    
    # 5秒待ってから追加のEnterを送信
    sleep 5
    tmux send-keys -t "$session" "" Enter
    
    # thinkモードの場合
    if [[ "$THINK_MODE" == true ]]; then
        sleep 1
        tmux send-keys -t "$session" "think" Enter
    fi
}

# ファイル監視
watch_review_files() {
    local session="$1"
    local watch_file="$TMP_DIR/gemini-review"
    
    log "Starting file watch on: $watch_file"
    
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
        inotifywait -e modify,create "$TMP_DIR" 2>/dev/null | while read -r dir event file; do
            if [[ "$file" == "gemini-review" ]]; then
                local filepath="$dir$file"
                log "Detected change in: $filepath"
                
                if [[ -f "$filepath" ]]; then
                    local content=$(cat "$filepath")
                    if [[ -n "$content" ]]; then
                        send_review_to_tmux "$session" "$content"
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
                send_review_to_tmux "$session" "$content"
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
    
    while true; do
        if [[ -f "$watch_file" ]]; then
            local current_mtime=$(stat -c %Y "$watch_file" 2>/dev/null || stat -f %m "$watch_file" 2>/dev/null)
            
            if [[ "$current_mtime" != "$last_mtime" ]]; then
                log "Detected file change: $watch_file (mtime: $current_mtime)"
                last_mtime="$current_mtime"
                
                local content=$(cat "$watch_file")
                if [[ -n "$content" ]]; then
                    log "Sending review content (${#content} chars) to session: $session"
                    send_review_to_tmux "$session" "$content"
                else
                    log "Warning: File exists but content is empty"
                fi
            fi
        else
            log "File not found: $watch_file (waiting...)"
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
    echo "Tmp directory: $TMP_DIR"
    echo "Think mode: $THINK_MODE"
    echo "Auto-launch Claude: $AUTO_CLAUDE_LAUNCH"
    echo "============================="
    
    log "Starting cc-gen-review with session: $SESSION_NAME"
    
    # tmuxセッションのセットアップ
    setup_tmux_session "$SESSION_NAME"
    
    # 一時ディレクトリのセットアップ
    setup_tmp_dir
    
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
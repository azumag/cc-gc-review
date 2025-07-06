#!/bin/bash

# cc-gc-review.sh - Claude Code と Gemini を stop hook 連携させるサポートツール

set -euo pipefail

# デフォルト値
SESSION_NAME=""
AUTO_CLAUDE_LAUNCH=false
TMP_DIR_BASE="/tmp"
TMP_DIR=""
WATCH_FILE=""
THINK_MODE=false
VERBOSE=false
CUSTOM_COMMAND=""
RESEND_EXISTING=false
MAX_REVIEWS=4
INFINITE_REVIEW=false
REVIEW_COUNT_FILE="/tmp/cc-gc-review-count"

# ログ関数
log() {
    if [[ $VERBOSE == true ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
    fi
}

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

# ヘルプ表示
show_help() {
    cat <<EOF
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
        -c | --auto-claude-launch)
            AUTO_CLAUDE_LAUNCH=true
            shift
            ;;
        --think)
            THINK_MODE=true
            shift
            ;;
        --custom-command)
            if [[ $# -lt 2 || -z $2 ]]; then
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
            if [[ $# -lt 2 || -z $2 ]]; then
                error "--max-reviews requires a number argument"
            fi
            MAX_REVIEWS="$2"
            shift 2
            ;;
        --infinite-review)
            INFINITE_REVIEW=true
            shift
            ;;
        -v | --verbose)
            VERBOSE=true
            shift
            ;;
        -h | --help)
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

    if [[ -z $SESSION_NAME ]]; then
        error "SESSION_NAME is required"
    fi
}

# tmuxセッション管理
setup_tmux_session() {
    local session="$1"

    # tmuxコマンドの存在確認
    if ! command -v tmux >/dev/null 2>&1; then
        error "tmux command not found. Please install tmux first."
    fi

    if ! tmux has-session -t "$session" 2>/dev/null; then
        log "Creating new tmux session: $session"
        if ! tmux new-session -d -s "$session"; then
            error "Failed to create tmux session: $session"
        fi

        if [[ $AUTO_CLAUDE_LAUNCH == true ]]; then
            log "Launching Claude in session: $session"
            if ! tmux send-keys -t "$session" "claude" Enter; then
                error "Failed to send keys to tmux session: $session"
            fi
            sleep 2
        fi
    else
        log "Using existing tmux session: $session"
    fi
}

# レビューカウントリセット機能（新仕様では自動リセットしない）
# この関数は将来的に削除予定
reset_review_count_if_needed() {
    local filepath="$1"
    # 新仕様では、ファイル更新時の自動リセットは行わない
    # カウントリセットは、リミット到達後の次回レビューパス時のみ
    log "File update detected: $filepath (auto-reset disabled in new specification)"
}

# レビュー結果をtmuxに送信
send_review_to_tmux() {
    local session="$1"
    local review_content="$2"

    # レビュー数制限チェック（無限レビューでない場合）
    if [[ $INFINITE_REVIEW == false ]]; then
        local current_count=0
        if [[ -f $REVIEW_COUNT_FILE ]]; then
            current_count=$(cat "$REVIEW_COUNT_FILE")
            # ファイルの内容が数値でない場合はリセット
            if ! [[ $current_count =~ ^[0-9]+$ ]]; then
                log "Invalid review count file content. Resetting."
                current_count=0
                rm -f "$REVIEW_COUNT_FILE"
            fi
        fi

        # リミットに達している場合は送信をパスしてカウントをリセット
        if [[ $current_count -ge $MAX_REVIEWS ]]; then
            echo " Review limit reached ($current_count/$MAX_REVIEWS). Passing this review and resetting count."
            log "Review limit reached. Skipping send and resetting count."
            # カウントをリセット
            echo "0" >"$REVIEW_COUNT_FILE"
            return 1
        fi
    fi

    echo " Review received (${#review_content} characters)"

    # thinkモードの場合はレビュー内容の末尾に追加
    if [[ $THINK_MODE == true ]]; then
        review_content="${review_content}

think"
        echo " Think mode enabled - appending 'think' command"
    fi

    # カスタムコマンドの場合はレビュー内容の先頭に追加（セキュリティ対策：英数字とハイフンのみ許可）
    if [[ -n $CUSTOM_COMMAND ]]; then
        if [[ $CUSTOM_COMMAND =~ ^[a-zA-Z0-9_-]+$ ]]; then
            review_content="/$CUSTOM_COMMAND ${review_content}"
            echo " Custom command enabled - prepending '/$CUSTOM_COMMAND'"
        else
            echo "⚠️  Warning: Custom command contains invalid characters. Ignoring: $CUSTOM_COMMAND"
        fi
    fi

    echo " Sending review to tmux session: $session"
    log "Review content preview: ${review_content:0:100}..."

    # レビュー内容を送信
    tmux send-keys -t "$session" "$review_content" Enter

    # 5秒待ってから追加のEnterを送信（Claude Codeのプロンプト処理を確実にするため）
    sleep 5
    tmux send-keys -t "$session" "" Enter
    # さらに5秒待ってから追加のEnterを送信（Claude Codeのプロンプト処理を確実にするため）
    sleep 5
    tmux send-keys -t "$session" "" Enter

    echo "✅ Review sent successfully"

    # 送信後にカウントを更新（無限レビューでない場合）
    if [[ $INFINITE_REVIEW == false ]]; then
        local current_count=0
        if [[ -f $REVIEW_COUNT_FILE ]]; then
            current_count=$(cat "$REVIEW_COUNT_FILE")
            if ! [[ $current_count =~ ^[0-9]+$ ]]; then
                log "Invalid review count file content. Resetting."
                current_count=0
            fi
        fi

        # カウントを+1（アトミックな操作でファイル書き込み）
        local new_count=$((current_count + 1))
        local temp_count_file
        temp_count_file=$(mktemp)
        echo "$new_count" >"$temp_count_file"
        mv "$temp_count_file" "$REVIEW_COUNT_FILE"
        echo " Review count: $new_count/$MAX_REVIEWS"

        # リミットに達したかチェック
        if [[ $new_count -ge $MAX_REVIEWS ]]; then
            echo "⚠️  Review limit will be reached. Next review will be passed and count will be reset."
        fi
    fi

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
    # テストモードの場合はスキップ
    if [[ ${CC_GC_REVIEW_TEST_MODE:-false} == "true" ]]; then
        echo "▶️  テストモード: 自動で続行します"
        return 0
    fi

    # バックグラウンド実行やパイプ経由の場合はスキップ
    if [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
        echo "▶️  バックグラウンド実行モード: 自動で続行します"
        return 0
    fi

    echo "続行します"
    echo "停止するには 'n' を入力してください (10秒後に自動で続行):"

    local input=""
    if read -t 10 -r input 2>/dev/null; then
        # ユーザーが何か入力した場合
        if [[ $input == "n" || $input == "N" ]]; then
            echo "❌ ユーザーによりレビューループを停止しました"
            return 2 # 停止を意味する特別な終了コード
        else
            echo "▶️  続行します"
            return 0 # 続行
        fi
    else
        # タイムアウトした場合（10秒経過）またはread失敗の場合
        echo "▶️  タイムアウトしました。続行します"
        return 0 # 続行
    fi
}

# レビューファイルを処理する共通関数
process_review_file() {
    local filepath="$1"
    local session="$2"

    log "Detected change in: $filepath"

    if [[ ! -f $filepath ]]; then
        log "File does not exist: $filepath"
        return
    fi

    local content
    content=$(cat "$filepath")
    if [[ -z $content ]]; then
        log "Warning: File exists but content is empty"
        return
    fi

    echo "🔔 New review detected!"

    # レビューカウントリセットチェック
    reset_review_count_if_needed "$filepath"

    set +e
    send_review_to_tmux "$session" "$content"
    local send_result=$?
    set -e

    if [[ $send_result -eq 1 ]]; then
        echo "⚠️  Review limit reached. Continuing to monitor..."
    elif [[ $send_result -eq 2 ]]; then
        echo "👋 Exiting watch mode by user request."
        exit 0
    fi
}

# ファイル監視
watch_review_files() {
    local session="$1"
    local watch_file="$WATCH_FILE"

    log "Starting file watch on: $watch_file"

    # 起動時の既存ファイルチェック
    if [[ -f $watch_file ]]; then
        if [[ $RESEND_EXISTING == true ]]; then
            log "Existing review file found, resending due to --resend option"
            local content
            content=$(cat "$watch_file")
            if [[ -n $content ]]; then
                echo "🔄 Resending existing review file..."
                set +e # Temporarily disable exit on error
                send_review_to_tmux "$session" "$content"
                local send_result=$?
                set -e # Re-enable exit on error

                if [[ $send_result -eq 1 ]]; then
                    echo "⚠️  Review limit reached during resend. Count has been reset. Continuing to monitor..."
                    # Continue to monitoring instead of exiting
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
        # Use a temporary file to avoid subshell issues with pipe
        local tmp_output
        tmp_output="$(mktemp)"
        local watch_dir
        watch_dir="$(dirname "$watch_file")"
        inotifywait -e modify,create "$watch_dir" 2>/dev/null >"$tmp_output"

        while read -r dir _ file; do
            if [[ $file == "$(basename "$watch_file")" ]]; then
                local filepath="$dir$file"
                process_review_file "$filepath" "$session"
            fi
        done <"$tmp_output"

        rm -f "$tmp_output"
    done
}

# fswatchを使った監視
watch_with_fswatch() {
    local session="$1"
    local watch_file="$2"

    log "Using fswatch for file monitoring"

    fswatch -0 "$watch_file" | while IFS= read -r -d '' filepath; do
        process_review_file "$filepath" "$session"
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
    if [[ -f $watch_file ]]; then
        last_mtime=$(stat -c %Y "$watch_file" 2>/dev/null || stat -f %m "$watch_file" 2>/dev/null)
        log "Initial file mtime: $last_mtime (skipping initial send)"
    fi

    while true; do
        if [[ -f $watch_file ]]; then
            local current_mtime
            current_mtime=$(stat -c %Y "$watch_file" 2>/dev/null || stat -f %m "$watch_file" 2>/dev/null)

            if [[ $current_mtime != "$last_mtime" ]]; then
                log "Detected file change: $watch_file (mtime: $current_mtime)"
                last_mtime="$current_mtime"
                process_review_file "$watch_file" "$session"
            fi
        fi
        sleep 2
    done
}

# シグナルハンドラー
cleanup() {
    log "Shutting down cc-gc-review..."
    if [[ -n $TMP_DIR && -d $TMP_DIR ]]; then
        log "Removing temporary directory: $TMP_DIR"
        rm -rf "$TMP_DIR"
    fi
    log "cc-gc-review shutdown complete."
}

trap cleanup INT TERM EXIT

# メイン処理
main() {
    parse_args "$@"

    # 安全な一時ディレクトリを作成
    TMP_DIR=$(mktemp -d "$TMP_DIR_BASE/cc-gc-review.XXXXXX")
    log "Created temporary directory: $TMP_DIR"

    WATCH_FILE="$TMP_DIR/gemini-review"
    # hook-handler.sh にもこのパスを渡すため環境変数で共有
    export CC_GC_REVIEW_WATCH_FILE="$WATCH_FILE"

    echo "=== cc-gc-review starting ==="
    echo "Session name: $SESSION_NAME"
    echo "Review file: $WATCH_FILE"
    echo "Max reviews: $MAX_REVIEWS"
    if [[ -n $CUSTOM_COMMAND ]]; then
        echo "Custom command: /$CUSTOM_COMMAND"
    fi
    if [[ $INFINITE_REVIEW == true ]]; then
        echo "Review limit: unlimited"
    else
        echo "Review limit: $MAX_REVIEWS"
    fi
    echo "============================="

    log "Starting cc-gc-review with session: $SESSION_NAME"

    # tmuxセッションのセットアップ
    setup_tmux_session "$SESSION_NAME"

    echo ""
    echo "✓ tmux session '$SESSION_NAME' is ready"
    echo "✓ Watching for review file: $WATCH_FILE"
    echo "✓ Log file: $LOG_FILE"
    echo ""
    echo "Press Ctrl+C to stop watching..."
    echo ""

    log "Session created. You can attach with: tmux attach-session -t $SESSION_NAME"

    # ファイル監視開始
    watch_review_files "$SESSION_NAME"
}

# エントリーポイント
if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
    main "$@"
fi

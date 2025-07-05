#!/bin/bash

# hook-handler.sh - Claude Codeのstop hookから呼び出されるハンドラー

# エラー時も継続するように変更
set -uo pipefail

# 設定
TMP_DIR="/tmp"
VERBOSE="${CC_GEN_REVIEW_VERBOSE:-false}"
GIT_DIFF_MODE=false
GIT_COMMIT_MODE=false
YOLO_MODE=false
LOG_FILE="/tmp/cc-gen-review-hook.log"

# ログ関数
log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] [hook-handler] $*"
    echo "$message" >> "$LOG_FILE"
    if [[ "$VERBOSE" == "true" ]]; then
        echo "$message" >&2
    fi
}

# ユーザー向けメッセージログ（必ず出力）
user_log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] [hook-handler] $*"
    echo "$message" >> "$LOG_FILE"
    echo "$message" >&2
}

error() {
    local message="[ERROR] [hook-handler] $*"
    echo "$message" >> "$LOG_FILE"
    echo "$message" >&2
    # hook環境では正常終了させる
    exit 0
}


# 作業サマリーの取得
get_work_summary() {
    local transcript_path="$1"
    
    if [[ ! -f "$transcript_path" ]]; then
        log "ERROR: Transcript file not found: $transcript_path"
        echo ""  # 空文字を返す
        return 0
    fi
    
    # 最後のassistantメッセージの内容を取得（エラーを無視）
    local summary=""
    summary=$(jq -r 'select(.type == "assistant")' "$transcript_path" 2>/dev/null | \
             jq -sr '.[-1].message.content[-1].text' 2>/dev/null || echo "")
    
    if [[ -z "$summary" ]]; then
        log "Warning: Could not extract work summary from transcript"
        summary=""  # 空文字を返す
    fi
    
    echo "$summary"
}

# Geminiでレビューを実行
run_gemini_review() {
    local summary="$1"
    local output_file="$2"
    
    log "Running Gemini review..."
    
    # Geminiプロンプトの作成
    local prompt="作業内容をレビューして、改善点や注意点があれば日本語で簡潔に指摘してください。良い点も含めてフィードバックをお願いします。"
    
    # --git-diffオプションが指定されている場合は追加の指示を含める
    if [[ "$GIT_DIFF_MODE" == "true" ]]; then
        prompt="$prompt

重要: 自分でgit diffを実行して作業ファイルの具体的な変更内容も把握してからレビューを行ってください。"
    fi
    
    # --git-commitオプションが指定されている場合は追加の指示を含める
    if [[ "$GIT_COMMIT_MODE" == "true" ]]; then
        prompt="$prompt

重要: 自分でgit commitを確認し、ファイルの変更内容を把握してからレビューを行ってください。"
    fi
    
    prompt="$prompt

作業内容:
$summary

レビュー結果:"
    
    # プロンプトを/tmp/gemini-promptに出力
    echo "$prompt" > "/tmp/gemini-prompt"
    log "Prompt written to: /tmp/gemini-prompt"
    
    # gemini-cliを使用してレビューを実行
    if command -v gemini >/dev/null 2>&1; then
        # gemini-cliがインストールされている場合
        local gemini_options="-s"
        if [[ "$YOLO_MODE" == "true" ]]; then
            gemini_options="$gemini_options -y"
        fi
        gemini_options="$gemini_options -p"
        
        # まずはProモデルで実行（標準出力と標準エラーを分離）
        log "Trying Gemini Pro model first..."
        local temp_stdout
        temp_stdout=$(mktemp)
        local temp_stderr
        temp_stderr=$(mktemp)
        local start_time
        start_time=$(date +%s)
        
        # geminiプロセスをタイムアウト付きで実行（手動管理）
        local gemini_timeout=120  # 2分でタイムアウト
        
        log "Manual timeout management for gemini execution (${gemini_timeout}s)"
        echo "$prompt" | gemini $gemini_options > "$temp_stdout" 2> "$temp_stderr" &
        local gemini_pid=$!
        log "Started gemini process with PID: $gemini_pid"
        
        # プロセス完了をタイムアウト付きで待つ
        local wait_count=0
        local gemini_exit_code=124  # デフォルトはタイムアウト
        while [[ $wait_count -lt $gemini_timeout ]]; do
            if ! kill -0 $gemini_pid 2>/dev/null; then
                # プロセス終了
                wait $gemini_pid
                local gemini_exit_code=$?
                log "Gemini process completed after ${wait_count} seconds with exit code: $gemini_exit_code"
                break
            fi
            sleep 1
            ((wait_count++))
            
            # 進捗ログ（10秒ごと）
            if [[ $((wait_count % 10)) -eq 0 ]]; then
                log "Waiting for gemini... ${wait_count}/${gemini_timeout}s"
            fi
        done
        
        # タイムアウト時の処理
        if [[ $wait_count -ge $gemini_timeout ]]; then
            log "Gemini process timeout after ${gemini_timeout} seconds, killing process"
            kill -TERM $gemini_pid 2>/dev/null || true
            sleep 2
            kill -KILL $gemini_pid 2>/dev/null || true
            wait $gemini_pid 2>/dev/null || true  # 確実にプロセス回収
            local gemini_exit_code=124  # timeout exit code
            log "Gemini process killed due to timeout"
        fi
        
        # 結果待機（短時間）
        local content_wait=5
        local content_count=0
        while [[ $content_count -lt $content_wait ]]; do
            if [[ -s "$temp_stdout" ]] || [[ -s "$temp_stderr" ]]; then
                local current_content=$(cat "$temp_stdout" 2>/dev/null)
                local filtered_content=$(echo "$current_content" | grep -v "^\[dotenv@.*\] injecting env" | sed '/^$/d')
                
                if [[ -n "$filtered_content" ]] || [[ $gemini_exit_code -ne 0 ]]; then
                    log "Content available after ${content_count} seconds"
                    break
                fi
            fi
            sleep 1
            ((content_count++))
        done
        
        local review_result
        review_result=$(cat "$temp_stdout" 2>/dev/null)
        local error_output
        error_output=$(cat "$temp_stderr" 2>/dev/null)
        
        # dotenvログを除去して実際のレビュー結果のみを抽出
        review_result=$(echo "$review_result" | grep -v "^\[dotenv@.*\] injecting env" | sed '/^$/d')
        
        # タイムアウトまたは実行失敗時の処理
        local is_rate_limit=false
        
        # 429エラー（レート制限）をチェック - 標準エラー出力とexit codeで判定
        # より包括的なレートリミットエラーパターンをチェック
        if [[ $gemini_exit_code -eq 124 ]]; then
            log "Gemini Pro model timed out after ${gemini_timeout} seconds"
            # タイムアウトをレート制限として扱い、Flashモデルに切り替え
            is_rate_limit=true
            log "Timeout detected, will switch to Flash model"
        elif [[ $gemini_exit_code -ne 0 ]] || [[ -z "$review_result" ]]; then
            # exit code != 0 の場合、または exit code = 0 でもレビュー結果が空の場合にレート制限をチェック
            if [[ "$error_output" =~ "status 429" ]] || \
               [[ "$error_output" =~ "rateLimitExceeded" ]] || \
               [[ "$error_output" =~ "Quota exceeded" ]] || \
               [[ "$error_output" =~ "RESOURCE_EXHAUSTED" ]] || \
               [[ "$error_output" =~ "Too Many Requests" ]] || \
               [[ "$error_output" =~ "Gemini 2.5 Pro Requests" ]] || \
               [[ "$review_result" =~ "status 429" ]]; then
                is_rate_limit=true
                log "Rate limit detected in error output (exit code: $gemini_exit_code)"
            elif [[ -z "$review_result" ]] && [[ $gemini_exit_code -eq 0 ]]; then
                log "Warning: No actual review content found after filtering dotenv logs"
                
                # 生の出力をログに記録（デバッグ用）
                local raw_output=$(cat "$temp_stdout" 2>/dev/null)
                log "Raw stdout content: $raw_output"
                log "Raw stderr content: $error_output"
                
                log "Skipping review due to empty content"
                return 1  # レビューファイルを作成しない
            fi
        fi
        
        if [[ "$is_rate_limit" == "true" ]]; then
            log "Rate limit detected for Pro model, switching to Flash model..."
            user_log "⚠️  Gemini Pro quota exceeded, switching to Flash model..."
            
            # Flashモデルで再実行
            gemini_options="$gemini_options --model=gemini-2.5-flash"
            local flash_start_time
            flash_start_time=$(date +%s)
            
            # Flashモデルもタイムアウト付きで実行（手動管理）
            log "Manual timeout management for Flash model execution (${gemini_timeout}s)"
            echo "$prompt" | gemini $gemini_options > "$temp_stdout" 2> "$temp_stderr" &
            local flash_pid=$!
            log "Started Flash model process with PID: $flash_pid"
            
            # プロセス完了をタイムアウト付きで待つ
            local flash_wait_count=0
            gemini_exit_code=124  # デフォルトはタイムアウト
            while [[ $flash_wait_count -lt $gemini_timeout ]]; do
                if ! kill -0 $flash_pid 2>/dev/null; then
                    wait $flash_pid
                    gemini_exit_code=$?
                    log "Flash model process completed after ${flash_wait_count} seconds with exit code: $gemini_exit_code"
                    break
                fi
                sleep 1
                ((flash_wait_count++))
                
                # 進捗ログ（10秒ごと）
                if [[ $((flash_wait_count % 10)) -eq 0 ]]; then
                    log "Waiting for Flash model... ${flash_wait_count}/${gemini_timeout}s"
                fi
            done
            
            # タイムアウト時の処理
            if [[ $flash_wait_count -ge $gemini_timeout ]]; then
                log "Flash model process timeout after ${gemini_timeout} seconds, killing process"
                kill -TERM $flash_pid 2>/dev/null || true
                sleep 2
                kill -KILL $flash_pid 2>/dev/null || true
                wait $flash_pid 2>/dev/null || true  # 確実にプロセス回収
                gemini_exit_code=124  # timeout exit code
                log "Flash model process killed due to timeout"
            fi
            
            # Flashモデルでも結果待機（短時間）
            local flash_content_wait=5
            local flash_content_count=0
            while [[ $flash_content_count -lt $flash_content_wait ]]; do
                if [[ -s "$temp_stdout" ]] || [[ -s "$temp_stderr" ]]; then
                    local current_content=$(cat "$temp_stdout" 2>/dev/null)
                    local filtered_content=$(echo "$current_content" | grep -v "^\[dotenv@.*\] injecting env" | sed '/^$/d')
                    
                    if [[ -n "$filtered_content" ]] || [[ $gemini_exit_code -ne 0 ]]; then
                        log "Flash model content available after ${flash_content_count} seconds"
                        break
                    fi
                fi
                sleep 1
                ((flash_content_count++))
            done
            
            review_result=$(cat "$temp_stdout" 2>/dev/null)
            error_output=$(cat "$temp_stderr" 2>/dev/null)
            
            # Flashモデルでもdotenvログを除去
            review_result=$(echo "$review_result" | grep -v "^\[dotenv@.*\] injecting env" | sed '/^$/d')
            
            if [[ $gemini_exit_code -eq 124 ]]; then
                log "Flash model also timed out after ${gemini_timeout} seconds"
                log "Both Pro and Flash models timed out - skipping review"
                return 1  # レビューファイルを作成しない
            elif [[ $gemini_exit_code -eq 0 ]]; then
                if [[ -z "$review_result" ]]; then
                    log "Warning: Flash model succeeded but no review content found after filtering"
                    local raw_flash_output=$(cat "$temp_stdout" 2>/dev/null)
                    log "Raw flash stdout content: $raw_flash_output"
                    log "Skipping review due to empty Flash content"
                    return 1  # レビューファイルを作成しない
                else
                    local flash_end_time=$(date +%s)
                    local flash_execution_time=$((flash_end_time - start_time))
                    log "Successfully switched to Flash model with content length: ${#review_result} (took ${flash_execution_time}s total)"
                    user_log "✅ Flash model execution successful"
                fi
            else
                log "Flash model also failed with exit code: $gemini_exit_code"
                log "Flash model error output: $error_output"
                log "Skipping review due to Flash model failure"
                return 1  # レビューファイルを作成しない
            fi
        elif [[ $gemini_exit_code -ne 0 ]]; then
            log "Gemini execution failed (non-rate-limit error) with exit code: $gemini_exit_code"
            log "Error output: $error_output"
            log "Skipping review due to Pro model failure"
            return 1  # レビューファイルを作成しない
        else
            local end_time=$(date +%s)
            local execution_time=$((end_time - start_time))
            log "Pro model execution successful with content length: ${#review_result} (took ${execution_time}s)"
        fi
        
        # 一時ファイルのクリーンアップ
        rm -f "$temp_stdout" "$temp_stderr"
    else
        # gemini-cliがない場合はスキップ
        log "Warning: gemini command not found, skipping review"
        return 1  # レビューファイルを作成しない
    fi
    
    # レビュー結果をファイルに書き込み
    echo "$review_result" > "$output_file"
    log "Review result written to: $output_file"
    
    # レビュー結果の内容をチェックして適切なexit codeを設定
    if [[ "$review_result" =~ ^\[自動レビュー\] ]]; then
        # エラーメッセージの場合でも、レビューファイルは作成されているので正常終了
        log "Review completed with fallback message"
        return 0
    else
        # 実際のレビュー内容が取得できた場合
        log "Review completed successfully with actual content"
        return 0
    fi
}

# オプション解析
parse_options() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --git-diff)
                GIT_DIFF_MODE=true
                YOLO_MODE=true  # --git-diffが指定された場合は自動的にYOLOモードも有効
                shift
                ;;
            --git-commit)
                GIT_COMMIT_MODE=true
                YOLO_MODE=true  # --git-commitが指定された場合は自動的にYOLOモードも有効
                shift
                ;;
            --yolo|-y)
                YOLO_MODE=true
                shift
                ;;
            *)
                # 不明なオプションは無視
                shift
                ;;
        esac
    done
    
    log "GIT_DIFF_MODE: $GIT_DIFF_MODE"
    log "GIT_COMMIT_MODE: $GIT_COMMIT_MODE"
    log "YOLO_MODE: $YOLO_MODE"
}

# メイン処理
main() {
    log "=== Hook handler started ==="
    log "Log file: $LOG_FILE"
    
    # オプション解析
    parse_options "$@"
    
    # 現在のディレクトリを取得（Claude Codeの作業ディレクトリ）
    local working_dir
    working_dir=$(pwd)
    log "Working directory: $working_dir"
    
    # 標準入力からJSONを読み取る
    local input
    input=$(cat)
    log "Received input: $input"
    
    # JSONパース
    local session_id
    session_id=$(echo "$input" | jq -r '.session_id' 2>/dev/null || echo "")
    local transcript_path
    transcript_path=$(echo "$input" | jq -r '.transcript_path' 2>/dev/null || echo "")
    local stop_hook_active
    stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active' 2>/dev/null || echo "false")
    
    # 必須パラメータのチェック
    if [[ -z "$transcript_path" ]]; then
        log "ERROR: transcript_path not found in input JSON - skipping review"
        exit 0
    fi
    
    # パスの展開（~を$HOMEに変換）
    transcript_path="${transcript_path/#\~/$HOME}"
    
    log "Session ID: $session_id"
    log "Transcript path: $transcript_path"
    log "Stop hook active: $stop_hook_active"
    log "Working directory: $working_dir"
    
    # stop_hook_activeがtrueの場合は無限ループを防ぐために終了
    if [[ "$stop_hook_active" == "true" ]]; then
        log "Stop hook is already active, exiting to prevent infinite loop"
        exit 0
    fi
    
    # 作業サマリーの取得
    local work_summary
    work_summary=$(get_work_summary "$transcript_path")
    log "Work summary extracted (${#work_summary} characters)"
    
    # 作業サマリーが空の場合はレビューをスキップ
    if [[ -z "$work_summary" ]]; then
        log "No work summary available - skipping review"
        exit 0
    fi
    
    # レビューファイル名
    local review_file="/tmp/gemini-review"
    
    # Geminiレビューの実行
    if run_gemini_review "$work_summary" "$review_file"; then
        log "=== Hook handler completed successfully ==="
        log "Review file written to: $review_file"
        log "Log file: $LOG_FILE"
    else
        log "=== Hook handler completed (review skipped) ==="
        log "No review file created due to errors"
        log "Log file: $LOG_FILE"
    fi
    
    # hookを正常終了させる
    exit 0
}

# エラーハンドリング（どんなエラーでも正常終了）
handle_error() {
    local exit_code=$?
    local line_no=$1
    log "Hook handler encountered error on line $line_no (exit code: $exit_code), exiting gracefully without creating review file..."
    exit 0
}

trap 'handle_error $LINENO' ERR

# エントリーポイント（エラーキャッチ付き）
{
    main "$@"
} || {
    log "Main function failed, exiting gracefully without creating review file..."
    exit 0
}
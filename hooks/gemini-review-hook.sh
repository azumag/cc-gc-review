#!/bin/bash

set -euo pipefail

# Parse command line arguments
DEBUG_MODE=false
while [[ $# -gt 0 ]]; do
    case $1 in
    --debug)
        DEBUG_MODE=true
        shift
        ;;
    *)
        # Unknown option, ignore and pass through
        shift
        ;;
    esac
done

# Source shared utilities
source "$(dirname "$0")/shared-utils.sh"

# Configuration constants
readonly CLAUDE_SUMMARY_MAX_LENGTH=1000
readonly CLAUDE_SUMMARY_PRESERVE_LENGTH=400
readonly GEMINI_TIMEOUT=300
readonly RATE_LIMITED_RESPONSE="REVIEW_RATE_LIMITED"
readonly TIMEOUT_EXIT_CODE=124
readonly REVIEW_COMPLETED_MARKER="REVIEW_COMPLETED"

# Debug log configuration (only when debug mode is enabled)
if [ "$DEBUG_MODE" = "true" ]; then
    readonly LOG_DIR="/tmp"
    readonly LOG_FILE="${LOG_DIR}/gemini-review-hook.log"
    readonly ERROR_LOG_FILE="${LOG_DIR}/gemini-review-error.log"
    # Output log directory for user reference
    echo "[gemini-review-hook] Debug logging enabled. Logs will be written to: $LOG_DIR" >&2
fi

# Cleanup function for temporary files
cleanup() {
    [ -n "${TEMP_STDOUT:-}" ] && rm -f "$TEMP_STDOUT"
    [ -n "${TEMP_STDERR:-}" ] && rm -f "$TEMP_STDERR"

    # Debug logs are preserved in /tmp for post-process debugging
    if [ "$DEBUG_MODE" = "true" ]; then
        echo "[gemini-review-hook] Debug logs preserved at: $LOG_DIR" >&2
    fi
}

# Logging function with level support
log_message() {
    local level="$1"
    local stage="$2"
    local message="$3"

    # Always log errors and warnings to /tmp for debugging, even when debug mode is off
    local timestamp
    timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    local log_entry="$timestamp [$level] [$stage] $message"

    if [ "$DEBUG_MODE" = "true" ]; then
        # Log to main log file
        echo "$log_entry" >>"$LOG_FILE"

        # Log errors to separate error log
        if [ "$level" = "ERROR" ]; then
            echo "$log_entry" >>"$ERROR_LOG_FILE"
        fi

        # Also output to stderr for immediate visibility in debug mode
        echo "$log_entry" >&2
    else
        # Even without debug mode, log errors and warnings for troubleshooting
        if [ "$level" = "ERROR" ] || [ "$level" = "WARN" ]; then
            echo "$log_entry" >>"/tmp/gemini-review-hook-error.log"
        fi
    fi
}

# Convenience functions for different log levels
debug_log() { log_message "DEBUG" "$1" "$2"; }
info_log() { log_message "INFO" "$1" "$2"; }
warn_log() { log_message "WARN" "$1" "$2"; }
error_log() { log_message "ERROR" "$1" "$2"; }

# Run Gemini with timeout handling and error management
run_gemini() {
    local model_args="$1"  # e.g., "" for Pro or "--model=gemini-2.5-flash" for Flash
    local log_prefix="$2"  # e.g., "GEMINI" or "FLASH"
    local prompt="$3"      # Review prompt to send
    
    debug_log "$log_prefix" "Starting Gemini execution with model args: $model_args"
    debug_log "$log_prefix" "Prompt length: ${#prompt} characters"
    
    # Execute with timeout if available
    if command -v timeout >/dev/null 2>&1; then
        # Use a temporary file to safely pass the prompt with special characters
        local temp_prompt=$(mktemp)
        echo "$prompt" > "$temp_prompt"
        timeout "${GEMINI_TIMEOUT}s" gemini -s -y $model_args < "$temp_prompt" >"$TEMP_STDOUT" 2>"$TEMP_STDERR"
        local exit_code=$?
        rm -f "$temp_prompt"
        return $exit_code
    else
        debug_log "$log_prefix" "timeout command not available, using manual timeout handling"
        >&2 echo "[gemini-review-hook] Warning: timeout command not available for $log_prefix model, using manual timeout handling"
        
        # Manual timeout management
        local temp_prompt=$(mktemp)
        echo "$prompt" > "$temp_prompt"
        gemini -s -y $model_args < "$temp_prompt" >"$TEMP_STDOUT" 2>"$TEMP_STDERR" &
        rm -f "$temp_prompt"
        local gemini_pid=$!
        
        local wait_count=0
        local exit_code=$TIMEOUT_EXIT_CODE
        while [[ $wait_count -lt $GEMINI_TIMEOUT ]]; do
            if ! kill -0 $gemini_pid 2>/dev/null; then
                wait $gemini_pid
                exit_code=$?
                break
            fi
            sleep 1
            ((wait_count++))
        done
        
        # Kill if timed out
        if [[ $wait_count -ge $GEMINI_TIMEOUT ]]; then
            kill -TERM $gemini_pid 2>/dev/null || true
            sleep 2
            kill -KILL $gemini_pid 2>/dev/null || true
            wait $gemini_pid 2>/dev/null || true
            exit_code=$TIMEOUT_EXIT_CODE
        fi
        
        return $exit_code
    fi
}

# Provide user-friendly error messages with actionable instructions
get_user_friendly_error() {
    local error_content="$1"
    
    if [[ "$error_content" =~ "command not found" ]]; then
        echo "gemini-cliがインストールされていません。インストールするには: npm install -g gemini-cli"
    elif [[ "$error_content" =~ "authentication" ]] || [[ "$error_content" =~ "auth" ]]; then
        echo "認証エラー（gemini-cliの認証が必要です）。認証するには: gemini auth"
    elif [[ "$error_content" =~ "Resource has been exhausted" ]] || [[ "$error_content" =~ "check quota" ]] || [[ "$error_content" =~ "RESOURCE_EXHAUSTED" ]]; then
        echo "クォータ制限エラー（APIの使用制限に達しました）。しばらく時間をおいてから再試行してください"
    elif [[ "$error_content" =~ "network" ]] || [[ "$error_content" =~ "connection" ]]; then
        echo "ネットワークエラー。インターネット接続を確認してください"
    else
        echo "Geminiサービスエラー: ${error_content:0:100}"
    fi
}


# Set trap for cleanup on script exit
trap cleanup EXIT

INPUT=$(cat)
info_log "START" "Script started, input received"
info_log "INPUT" "Received input: $INPUT"

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path')
debug_log "TRANSCRIPT" "Processing session_id: $SESSION_ID"
debug_log "TRANSCRIPT" "Processing transcript path: $TRANSCRIPT_PATH"
debug_log "TRANSCRIPT" "Raw input JSON: $INPUT"
debug_log "TRANSCRIPT" "File existence check: $(test -f "$TRANSCRIPT_PATH" && echo "EXISTS" || echo "NOT_FOUND")"

# Validate session ID consistency
validate_session_id() {
    local expected_session_id="$1"
    local transcript_path="$2"
    
    # Extract session ID from transcript path
    local path_session_id
    path_session_id=$(basename "$transcript_path" .jsonl)
    
    debug_log "SESSION_VALIDATION" "Expected session ID: $expected_session_id"
    debug_log "SESSION_VALIDATION" "Path-derived session ID: $path_session_id"
    
    if [ "$expected_session_id" != "$path_session_id" ]; then
        warn_log "SESSION_VALIDATION" "Session ID mismatch: expected=$expected_session_id, path=$path_session_id"
        return 1
    fi
    
    debug_log "SESSION_VALIDATION" "Session ID validation passed"
    return 0
}

# Handle backwards compatibility - if session_id is not provided, derive it from transcript path
if [ -z "$SESSION_ID" ] || [ "$SESSION_ID" = "null" ]; then
    if [ -n "$TRANSCRIPT_PATH" ] && [ "$TRANSCRIPT_PATH" != "null" ]; then
        SESSION_ID=$(basename "$TRANSCRIPT_PATH" .jsonl)
        debug_log "SESSION" "Session ID derived from transcript path: $SESSION_ID"
    else
        warn_log "SESSION" "No session ID or transcript path provided, skipping review"
        echo "[gemini-review-hook] Warning: No session ID or transcript path provided, skipping review" >&2
        safe_exit "No session ID or transcript path provided, review skipped" "approve"
    fi
fi

if [ -z "$TRANSCRIPT_PATH" ] || [ "$TRANSCRIPT_PATH" = "null" ]; then
    warn_log "TRANSCRIPT" "Transcript path is null or empty, skipping review"
    echo "[gemini-review-hook] Warning: No transcript path provided, skipping review" >&2
    safe_exit "No transcript path provided, review skipped" "approve"
fi

# Only validate session ID consistency if we have both session_id and transcript_path from input
# Skip validation for backwards compatibility when session_id was derived from transcript_path
if echo "$INPUT" | jq -e '.session_id' >/dev/null 2>&1; then
    if ! validate_session_id "$SESSION_ID" "$TRANSCRIPT_PATH"; then
        warn_log "SESSION_VALIDATION" "Session ID validation failed, attempting to find correct transcript"
        echo "[gemini-review-hook] Warning: Session ID mismatch detected" >&2
        
        # Try to find the correct transcript file for this session
        TRANSCRIPT_DIR=$(dirname "$TRANSCRIPT_PATH")
        CORRECT_TRANSCRIPT="$TRANSCRIPT_DIR/$SESSION_ID.jsonl"
        
        if [ -f "$CORRECT_TRANSCRIPT" ]; then
            warn_log "SESSION_VALIDATION" "Found correct transcript for session: $CORRECT_TRANSCRIPT"
            echo "[gemini-review-hook] Using correct transcript file: $CORRECT_TRANSCRIPT" >&2
            TRANSCRIPT_PATH="$CORRECT_TRANSCRIPT"
        else
            warn_log "SESSION_VALIDATION" "Correct transcript not found: $CORRECT_TRANSCRIPT"
            echo "[gemini-review-hook] Warning: Correct transcript file not found, will continue with original path" >&2
        fi
    fi
else
    debug_log "SESSION_VALIDATION" "No session_id in input, skipping validation (backwards compatibility)"
fi

# Wait for transcript file to be created (up to 10 seconds)
WAIT_COUNT=0
MAX_WAIT=10
while [ ! -f "$TRANSCRIPT_PATH" ] && [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    debug_log "TRANSCRIPT" "Waiting for transcript file to be created (attempt $((WAIT_COUNT + 1))/$MAX_WAIT)"
    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
done

# If file still doesn't exist after waiting, try to find the latest transcript file
if [ ! -f "$TRANSCRIPT_PATH" ]; then
    warn_log "TRANSCRIPT" "Specified transcript file not found: '$TRANSCRIPT_PATH'"
    
    # Try to find the latest transcript file in the same directory
    TRANSCRIPT_DIR=$(dirname "$TRANSCRIPT_PATH")
    if [ -d "$TRANSCRIPT_DIR" ]; then
        LATEST_TRANSCRIPT=$(find_latest_transcript_in_dir "$TRANSCRIPT_DIR")
        find_exit=$?
        handle_transcript_find_result "$find_exit" "$LATEST_TRANSCRIPT" "gemini-review-hook" "review" "$TRANSCRIPT_DIR"
    else
        warn_log "TRANSCRIPT" "Transcript directory not found: '$TRANSCRIPT_DIR'"
        echo "[gemini-review-hook] Warning: Transcript directory not found, skipping review" >&2
        safe_exit "Transcript directory not found, review skipped" "approve"
    fi
fi

debug_log "TRANSCRIPT" "Transcript file found after ${WAIT_COUNT}s wait"

if [ -f "$TRANSCRIPT_PATH" ]; then
    debug_log "TRANSCRIPT" "Transcript file found, extracting last messages"
    debug_log "TRANSCRIPT" "File size: $(wc -l < "$TRANSCRIPT_PATH") lines"
    debug_log "TRANSCRIPT" "File last modified: $(stat -f "%Sm" "$TRANSCRIPT_PATH")"
    
    LAST_MESSAGES=$(extract_last_assistant_message "$TRANSCRIPT_PATH" 0 true)
    debug_log "TRANSCRIPT" "Extracted message length: ${#LAST_MESSAGES} characters"
    
    if [ -z "$LAST_MESSAGES" ]; then
        debug_log "TRANSCRIPT" "No assistant messages found in transcript"
        # Try to check what's actually in the file
        debug_log "TRANSCRIPT" "Last 3 lines of transcript:"
        tail -3 "$TRANSCRIPT_PATH" | while read -r line; do
            debug_log "TRANSCRIPT" "Line: $line"
        done
    else
        debug_log "TRANSCRIPT" "First 100 chars of extracted message: ${LAST_MESSAGES:0:100}"
    fi
    
    if [ -n "$LAST_MESSAGES" ] && echo "$LAST_MESSAGES" | grep -q "$REVIEW_COMPLETED_MARKER"; then
        debug_log "TRANSCRIPT" "Found REVIEW_COMPLETED marker, exiting"
        safe_exit "Review already completed" "approve"
    fi
    if [ -n "$LAST_MESSAGES" ] && echo "$LAST_MESSAGES" | grep -q "$RATE_LIMITED_RESPONSE"; then
        debug_log "TRANSCRIPT" "Found RATE_LIMITED marker, exiting"
        safe_exit "Review rate limited" "approve"
    fi
    debug_log "TRANSCRIPT" "No exit conditions found, continuing"
else
    debug_log "TRANSCRIPT" "Transcript file not found or not accessible"
fi

PRINCIPLES=$(
    cat <<'EOF'
## 原則
- Gemini のレビュー内容を受けて行動せよ. ただし盲信はしないこと
- 改善点を指摘された場合は、その改善点に従って修正せよ
- 修正後は [REVIEW_COMPLETED] を表示せず、再度レビューを受けること
- レビュー内容に問題がなく、改善点がすべてクリアになった場合のみ「REVIEW_COMPLETED」とだけ発言せよ
- レビュー内容が空、もしくは「REVIEW_RATE_LIMITED」とだけ書かれていた場合は、「REVIEW_RATE_LIMITED」とだけ発言せよ
EOF
)

CLAUDE_SUMMARY=""
if [ -f "$TRANSCRIPT_PATH" ]; then
    debug_log "CLAUDE_SUMMARY" "Extracting Claude's last summary from transcript"
    # Extract Claude's last summary from transcript (JSONL format)
    # NOTE: This depends on Claude Code's transcript JSONL structure
    # If Claude Code changes its output format, this may need updates
    CLAUDE_SUMMARY=$(extract_last_assistant_message "$TRANSCRIPT_PATH" 0 true)

    # Check if extraction was successful
    if [ -z "$CLAUDE_SUMMARY" ]; then
        warn_log "CLAUDE_SUMMARY" "Failed to extract Claude summary (no assistant messages found)"
        echo "[gemini-review-hook] Warning: Failed to extract Claude summary from transcript (no assistant messages found)" >&2
    else
        debug_log "CLAUDE_SUMMARY" "Successfully extracted Claude summary (${#CLAUDE_SUMMARY} characters)"
    fi

    # Limit CLAUDE_SUMMARY to configured length to avoid token limit
    # Use character-aware truncation instead of byte-based to handle multibyte characters safely
    original_length=${#CLAUDE_SUMMARY}
    if [ "$original_length" -gt "$CLAUDE_SUMMARY_MAX_LENGTH" ]; then
        # Preserve important parts: first N chars + last N chars with separator
        FIRST_PART=$(printf "%.${CLAUDE_SUMMARY_PRESERVE_LENGTH}s" "$CLAUDE_SUMMARY")
        LAST_PART=$(echo "$CLAUDE_SUMMARY" | rev | cut -c1-${CLAUDE_SUMMARY_PRESERVE_LENGTH} | rev)
        CLAUDE_SUMMARY="${FIRST_PART}...(中略)...${LAST_PART}"
        debug_log "CLAUDE_SUMMARY" "Content truncated to preserve beginning and end (original: $original_length chars)"
    fi
fi

# Gather git information for review context
GIT_STATUS=""
GIT_DIFF=""
GIT_LOG=""

# Git diff size limit to prevent prompt overflow (characters)
# Can be overridden by GEMINI_DIFF_MAX_SIZE environment variable
readonly GIT_DIFF_MAX_SIZE="${GEMINI_DIFF_MAX_SIZE:-3000}"

if git rev-parse --git-dir >/dev/null 2>&1; then
    debug_log "GIT" "Gathering git information for review context"

    # Get git status
    GIT_STATUS=$(git status --porcelain 2>/dev/null || echo "Unable to get git status")

    # Get file list of changes instead of full diff to avoid overwhelming the prompt
    GIT_DIFF_FILES=$(git diff --name-status HEAD 2>/dev/null || echo "")
    if [ -z "$GIT_DIFF_FILES" ]; then
        # If no diff from HEAD, try staged changes
        GIT_DIFF_FILES=$(git diff --name-status --cached 2>/dev/null || echo "")
    fi
    
    if [ -n "$GIT_DIFF_FILES" ]; then
        # Show file list with change type (A=Added, M=Modified, D=Deleted)
        GIT_DIFF="変更されたファイル一覧:\n$GIT_DIFF_FILES\n\n詳細な差分は 'git diff HEAD' で確認してください"
        debug_log "GIT" "Git diff files: $(echo "$GIT_DIFF_FILES" | wc -l) files changed"
    else
        GIT_DIFF="変更なし"
    fi

    # Get recent commit log
    GIT_LOG=$(git log --oneline -n 3 2>/dev/null || echo "Unable to get git log")

    debug_log "GIT" "Git status length: ${#GIT_STATUS}, diff length: ${#GIT_DIFF}, log length: ${#GIT_LOG}"
else
    debug_log "GIT" "Not in a git repository"
fi

REVIEW_PROMPT=$(
    cat <<EOF
作業内容を厳正にレビューして、改善点を指摘してください。
Git 情報や Claude の作業まとめが空の場合は、自ら git diff やコミット確認を行って実際の変更内容を把握してください。

## レビュー観点:
- YAGNI：今必要じゃない機能は作らない
- DRY：同じコードを繰り返さない
- KISS：シンプルに保つ
- t-wada TDD：テスト駆動開発

## Git の現在の状態:

### Git Status:
${GIT_STATUS:-変更なし}

### Git Diff (最近の変更):
${GIT_DIFF:-変更なし}

### 最近のコミット履歴:
${GIT_LOG:-コミット履歴が取得できませんでした}

## Claude の最後の発言（作業まとめ）:
${CLAUDE_SUMMARY:-作業まとめが取得できませんでした}
EOF
)

# Try Pro model first with timeout and process monitoring
TEMP_STDOUT=$(mktemp)
TEMP_STDERR=$(mktemp)
debug_log "GEMINI" "Temporary files created: stdout=$TEMP_STDOUT, stderr=$TEMP_STDERR"

# Run Gemini Pro model
debug_log "GEMINI" "Prompt length: ${#REVIEW_PROMPT} characters"
debug_log "GEMINI" "Prompt preview ${REVIEW_PROMPT}"
GEMINI_EXIT_CODE=0
run_gemini "" "GEMINI" "$REVIEW_PROMPT" || GEMINI_EXIT_CODE=$?

GEMINI_REVIEW=$(cat "$TEMP_STDOUT" 2>/dev/null)
ERROR_OUTPUT=$(cat "$TEMP_STDERR" 2>/dev/null)
debug_log "GEMINI" "Gemini Pro execution completed with exit code: $GEMINI_EXIT_CODE"
debug_log "GEMINI" "Review length: ${#GEMINI_REVIEW} characters, Error length: ${#ERROR_OUTPUT} characters"

# Check for rate limit errors
IS_RATE_LIMIT=false
if [[ $GEMINI_EXIT_CODE -eq $TIMEOUT_EXIT_CODE ]]; then
    # Timeout - treat as rate limit
    warn_log "RATE_LIMIT" "Timeout detected (exit code $TIMEOUT_EXIT_CODE), treating as rate limit"
    IS_RATE_LIMIT=true
elif [[ $GEMINI_EXIT_CODE -ne 0 ]] || [[ -z $GEMINI_REVIEW ]]; then
    debug_log "RATE_LIMIT" "Checking error patterns for rate limit detection"

    # Rate limit error patterns for improved maintainability
    RATE_LIMIT_PATTERNS=(
        "status 429"
        "rateLimitExceeded"
        "Quota exceeded"
        "RESOURCE_EXHAUSTED"
        "Resource has been exhausted"
        "check quota"
        "Too Many Requests"
        "Gemini 2\.5 Pro Requests" # Note: Properly escaped for regex
    )

    # Check each pattern
    for pattern in "${RATE_LIMIT_PATTERNS[@]}"; do
        if [[ $ERROR_OUTPUT =~ $pattern ]]; then
            debug_log "RATE_LIMIT" "Rate limit pattern detected: $pattern"
            IS_RATE_LIMIT=true
            break
        fi
    done

    if [[ $IS_RATE_LIMIT != "true" ]]; then
        debug_log "ERROR" "Non-rate-limit error detected: exit code $GEMINI_EXIT_CODE"
    fi
fi

if [[ $IS_RATE_LIMIT == "true" ]]; then
    # Rate limited - try Flash model
    debug_log "FLASH" "Rate limit detected, switching to Flash model"
    >&2 echo "[gemini-review-hook] Rate limit detected, switching to Flash model..."

    # Run Gemini Flash model
    GEMINI_EXIT_CODE=0
    run_gemini "--model=gemini-2.5-flash" "FLASH" "$REVIEW_PROMPT" || GEMINI_EXIT_CODE=$?

    GEMINI_REVIEW=$(cat "$TEMP_STDOUT" 2>/dev/null)
    debug_log "FLASH" "Flash model output captured, length: ${#GEMINI_REVIEW} characters"
    debug_log "FLASH" "Gemini's review: $GEMINI_REVIEW"
    debug_log "FLASH" "Flash model execution completed with exit code: $GEMINI_EXIT_CODE"
    if [[ $GEMINI_EXIT_CODE -ne 0 ]] || [[ -z $GEMINI_REVIEW ]]; then
        debug_log "FLASH" "Flash model also failed, setting $RATE_LIMITED_RESPONSE"
        GEMINI_REVIEW="$RATE_LIMITED_RESPONSE"
    else
        debug_log "FLASH" "Flash model succeeded, review length: ${#GEMINI_REVIEW} characters"
    fi
elif [[ $GEMINI_EXIT_CODE -ne 0 ]]; then
    # Other error - provide error details to user
    error_log "ERROR" "Non-rate-limit error occurred: exit code $GEMINI_EXIT_CODE"
    error_log "ERROR" "Error output: $ERROR_OUTPUT"
    error_log "ERROR" "Review prompt was: $REVIEW_PROMPT"
    ERROR_REASON="Gemini execution failed with exit code $GEMINI_EXIT_CODE"
    if [ -n "$ERROR_OUTPUT" ]; then
        ERROR_REASON="$ERROR_REASON. Error: $ERROR_OUTPUT"
    fi
    safe_exit "$ERROR_REASON" "block"
fi

# Check for empty GEMINI_REVIEW and handle appropriately
if [[ -z "$GEMINI_REVIEW" ]]; then
    warn_log "REVIEW" "Empty review detected, analyzing failure cause"
    
    # Determine failure cause for better user feedback
    FAILURE_CAUSE="不明なエラー"
    if [[ ! -f "$TEMP_STDOUT" ]]; then
        FAILURE_CAUSE="一時ファイル作成に失敗"
        error_log "REVIEW" "Temporary stdout file not found: $TEMP_STDOUT"
    elif [[ ! -f "$TEMP_STDERR" ]]; then
        FAILURE_CAUSE="一時ファイル作成に失敗"
        error_log "REVIEW" "Temporary stderr file not found: $TEMP_STDERR"
    elif [[ -s "$TEMP_STDERR" ]]; then
        # Error output exists, use user-friendly error messages
        ERROR_CONTENT=$(cat "$TEMP_STDERR" 2>/dev/null)
        FAILURE_CAUSE=$(get_user_friendly_error "$ERROR_CONTENT")
        error_log "REVIEW" "Error output detected: $ERROR_CONTENT"
    elif [[ $GEMINI_EXIT_CODE -eq $TIMEOUT_EXIT_CODE ]]; then
        FAILURE_CAUSE="タイムアウト"
        error_log "REVIEW" "Timeout detected (exit code $TIMEOUT_EXIT_CODE)"
    elif [[ $GEMINI_EXIT_CODE -ne 0 ]]; then
        FAILURE_CAUSE="Gemini実行エラー (終了コード: $GEMINI_EXIT_CODE)"
        error_log "REVIEW" "Non-zero exit code: $GEMINI_EXIT_CODE"
    fi
    
    GEMINI_REVIEW="レビューの取得に失敗しました。原因: $FAILURE_CAUSE"
    warn_log "REVIEW" "Set fallback review message: $GEMINI_REVIEW"
fi

# Check if review indicates completion or rate limiting
DECISION="block"

# Safely combine review and principles, handling potential JSON content in GEMINI_REVIEW
COMBINED_CONTENT=$(printf "%s\n\n%s" "レビュー内容：$GEMINI_REVIEW" "$PRINCIPLES")
COMBINED_REASON=$(echo "$COMBINED_CONTENT" | jq -Rs .)

info_log "OUTPUT" "Returning decision: $DECISION"
info_log "OUTPUT" "Review content length: ${#GEMINI_REVIEW} characters"

cat <<EOF
{
  "decision": "$DECISION",
  "reason": $COMBINED_REASON
}
EOF

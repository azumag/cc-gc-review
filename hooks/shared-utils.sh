#!/bin/bash
# Shared utilities for Claude Code review scripts

set -euo pipefail

# Logging functions for basic output
log_info() {
    echo "INFO: $*"
}

log_warning() {
    echo "WARNING: $*" >&2
}

log_error() {
    echo "ERROR: $*" >&2
}

# Function to output safe JSON and exit with appropriate exit code
# 
# DESIGN RATIONALE - Consistent JSON Output Strategy:
# This function ALWAYS outputs JSON to ensure uniform interface between hook scripts and CI systems.
# Benefits:
# - Consistent machine-readable output format across all hook exit scenarios
# - Simplified parsing logic for CI systems and automation tools  
# - Clear separation between human-readable logs (stderr) and structured data (stdout)
# - Enables reliable automation and monitoring of hook execution results
# - Future-proof interface that can be extended with additional metadata
#
# This ensures consistent JSON output and proper shell exit codes for CI systems
safe_exit() {
    local reason="${1:-Script terminated safely}"
    local decision="${2:-approve}"
    
    # Safely escape the reason for JSON
    local escaped_reason
    escaped_reason=$(echo "$reason" | jq -Rs .)
    
    cat <<EOF
{
  "decision": "$decision",
  "reason": $escaped_reason
}
EOF

    # Expected schema:
    # {
    #   "continue": "boolean (optional)",
    #   "suppressOutput": "boolean (optional)",
    #   "stopReason": "string (optional)",
    #   "decision": "\"approve\" | \"block\" (optional)",
    #   "reason": "string (optional)"
    # }
    
    # Return appropriate exit code based on decision
    # - "block" decisions return exit 1 (failure) to signal CI systems
    # - "approve" decisions return exit 0 (success) to let CI continue
    # This dual approach ensures compatibility with both JSON-aware and exit-code-only CI systems
    if [ "$decision" = "block" ]; then
        exit 1
    else
        exit 0
    fi
}

# Function to find latest transcript file using cross-platform stat command
# 
# ROBUST ERROR HANDLING:
# This function provides comprehensive error detection and reporting for all failure modes.
# Callers MUST check exit codes to handle errors appropriately.
#
# Usage: find_latest_transcript_in_dir "directory_path"
# Returns: path to the latest .jsonl file (on success only)
# Exit codes: 
#   0 = success (latest file path written to stdout)
#   1 = directory not found or not accessible
#   2 = no .jsonl files found in directory  
#   3 = stat command error (file system or permission issues)
# 
# Debug mode: Set HOOK_DEBUG=true to enable detailed error logging to stderr
find_latest_transcript_in_dir() {
    local transcript_dir="$1"
    local debug_mode="${HOOK_DEBUG:-false}"
    
    if [ ! -d "$transcript_dir" ]; then
        [ "$debug_mode" = "true" ] && echo "DEBUG: Directory not found: $transcript_dir" >&2
        return 1
    fi
    
    # Check if any .jsonl files exist
    if ! find "$transcript_dir" -name "*.jsonl" -type f -print -quit | grep -q .; then
        [ "$debug_mode" = "true" ] && echo "DEBUG: No .jsonl files found in: $transcript_dir" >&2
        return 2
    fi
    
    local latest_file
    
    # Use compatible stat command for both macOS and Linux with robust error handling
    local stat_output
    local stat_errors
    
    if stat -f "%m %N" /dev/null >/dev/null 2>&1; then
        # macOS/BSD stat
        if ! stat_output=$(find "$transcript_dir" -name "*.jsonl" -type f -exec stat -f "%m %N" {} \; 2>/dev/null); then
            [ "$debug_mode" = "true" ] && echo "DEBUG: stat command failed on macOS" >&2
            return 3
        fi
    else
        # GNU stat (Linux)
        if ! stat_output=$(find "$transcript_dir" -name "*.jsonl" -type f -exec stat -c "%Y %n" {} \; 2>/dev/null); then
            [ "$debug_mode" = "true" ] && echo "DEBUG: stat command failed on Linux" >&2
            return 3
        fi
    fi
    
    # Process the stat output to find the latest file
    # Note: stat_output should not be empty here since we already verified files exist
    if [ -z "$stat_output" ]; then
        [ "$debug_mode" = "true" ] && echo "DEBUG: No stat output received despite files existing" >&2
        return 3
    fi
    
    latest_file=$(echo "$stat_output" | sort -rn | head -1 | cut -d' ' -f2-)
    
    if [ -n "$latest_file" ] && [ -f "$latest_file" ]; then
        echo "$latest_file"
        return 0
    else
        [ "$debug_mode" = "true" ] && echo "DEBUG: No valid latest file found in: $transcript_dir" >&2
        return 2
    fi
}

# Function to handle transcript find result with standardized error messages
# Usage: handle_transcript_find_result find_exit_code latest_transcript_path hook_name action_name
# Parameters:
#   find_exit_code: Exit code from find_latest_transcript_in_dir
#   latest_transcript_path: Path returned by find_latest_transcript_in_dir (may be empty)
#   hook_name: Name of the calling hook (e.g. "ci-monitor-hook", "gemini-review-hook")
#   action_name: Action being performed (e.g. "monitoring", "review")
# Returns: 0 if transcript found and path set in TRANSCRIPT_PATH, exits with safe_exit otherwise
handle_transcript_find_result() {
    local find_exit=$1
    local latest_transcript=$2
    local hook_name=$3
    local action_name=$4
    local transcript_dir=$5
    
    case $find_exit in
        0)
            warn_log "TRANSCRIPT" "Using latest transcript file instead: '$latest_transcript'"
            echo "[$hook_name] Warning: Using latest transcript file: '$latest_transcript'" >&2
            TRANSCRIPT_PATH="$latest_transcript"
            return 0
            ;;
        1)
            warn_log "TRANSCRIPT" "Transcript directory not found: '$transcript_dir'"
            echo "[$hook_name] Warning: Transcript directory not found, skipping $action_name" >&2
            safe_exit "Transcript directory not found, $action_name skipped" "approve"
            ;;
        2)
            warn_log "TRANSCRIPT" "No transcript files found in directory: '$transcript_dir'"
            echo "[$hook_name] Warning: No transcript files found, skipping $action_name" >&2
            safe_exit "No transcript files found, $action_name skipped" "approve"
            ;;
        3)
            warn_log "TRANSCRIPT" "Error accessing transcript files in directory: '$transcript_dir'"
            echo "[$hook_name] Warning: Error accessing transcript files, skipping $action_name" >&2
            safe_exit "Error accessing transcript files, $action_name skipped" "approve"
            ;;
        *)
            warn_log "TRANSCRIPT" "Unexpected error finding transcript files in directory: '$transcript_dir'"
            echo "[$hook_name] Warning: Unexpected error finding transcript files, skipping $action_name" >&2
            safe_exit "Unexpected error finding transcript files, $action_name skipped" "approve"
            ;;
    esac
}

# Function to extract last assistant message from JSONL transcript
extract_last_assistant_message() {
    local transcript_path="$1"
    local line_limit="${2:-0}"       # 0 means no limit
    local full_content="${3:-false}" # true to get full content, false for last line only

    if [ ! -f "$transcript_path" ]; then
        echo "Error: Transcript file not found: '$transcript_path'" >&2
        return 1
    fi

    local result=""

    if [ "$line_limit" -gt 0 ]; then
        # Get from last N lines, but restrict to the last assistant message with text content
        local last_text_uuid
        if ! last_text_uuid=$(tail -n "$line_limit" "$transcript_path" | jq -r 'select(.type == "assistant" and (.message.content[]? | select(.type == "text"))) | .uuid' | tail -1); then
            echo "Error: Failed to parse transcript JSON from '$transcript_path'" >&2
            return 1
        fi

        if [ -n "$last_text_uuid" ]; then
            # Get the last line of text content from that specific message
            if ! result=$(tail -n "$line_limit" "$transcript_path" | jq -r --arg uuid "$last_text_uuid" 'select(.type == "assistant" and .uuid == $uuid) | .message.content[] | select(.type == "text") | .text' | tail -n 1); then
                echo "Error: Failed to parse transcript JSON from '$transcript_path'" >&2
                return 1
            fi
        fi
    else
        if [ "$full_content" = "true" ]; then
            # Get ALL text content from the last assistant message WITH TEXT
            # First find the UUID of the last assistant message that has text content
            local last_text_uuid
            if ! last_text_uuid=$(jq -r 'select(.type == "assistant" and (.message.content[]? | select(.type == "text"))) | .uuid' < "$transcript_path" | tail -1); then
                echo "Error: Failed to parse transcript JSON from '$transcript_path'" >&2
                return 1
            fi

            if [ -n "$last_text_uuid" ]; then
                # Get all text content from that specific message, joined together
                if ! result=$(jq -r --arg uuid "$last_text_uuid" 'select(.type == "assistant" and .uuid == $uuid) | .message.content[] | select(.type == "text") | .text' < "$transcript_path"); then
                    echo "Error: Failed to parse transcript JSON from '$transcript_path'" >&2
                    return 1
                fi
            fi
        else
            # Get the last line of text content from the last assistant message with text content
            local last_text_uuid
            if ! last_text_uuid=$(jq -r 'select(.type == "assistant" and (.message.content[]? | select(.type == "text"))) | .uuid' < "$transcript_path" | tail -1); then
                echo "Error: Failed to parse transcript JSON from '$transcript_path'" >&2
                return 1
            fi

            if [ -n "$last_text_uuid" ]; then
                # Get the last line of text content from that specific message
                if ! result=$(jq -r --arg uuid "$last_text_uuid" 'select(.type == "assistant" and .uuid == $uuid) | .message.content[] | select(.type == "text") | .text' < "$transcript_path" | tail -1); then
                    echo "Error: Failed to parse transcript JSON from '$transcript_path'" >&2
                    return 1
                fi
            fi
        fi
    fi

    echo "$result"
}

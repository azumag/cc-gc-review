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
# Usage: find_latest_transcript_in_dir "directory_path"
# Returns: path to the latest .jsonl file or empty string if none found
find_latest_transcript_in_dir() {
    local transcript_dir="$1"
    
    if [ ! -d "$transcript_dir" ]; then
        return 1
    fi
    
    # Use compatible stat command for both macOS and Linux
    if stat -f "%m %N" /dev/null >/dev/null 2>&1; then
        # macOS/BSD stat
        find "$transcript_dir" -name "*.jsonl" -type f -exec stat -f "%m %N" {} \; 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-
    else
        # GNU stat (Linux)
        find "$transcript_dir" -name "*.jsonl" -type f -exec stat -c "%Y %n" {} \; 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-
    fi
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

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
                if ! result=$(jq -r --arg uuid "$last_text_uuid" 'select(.type == "assistant" and .uuid == $uuid) | .message.content[] | select(.type == "text") | .text' < "$transcript_path" | tr '\n' ' '); then
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

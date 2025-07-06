#!/bin/bash
# Shared utilities for Claude Code review scripts

set -euo pipefail

# Function to extract last assistant message from JSONL transcript
extract_last_assistant_message() {
    local transcript_path="$1"
    local line_limit="${2:-0}" # 0 means no limit
    local full_content="${3:-false}" # true to get full content, false for last line only

    if [ ! -f "$transcript_path" ]; then
        echo "Error: Transcript file not found: '$transcript_path'" >&2
        return 1
    fi

    local jq_filter_base='select(.type == "assistant" and .message.content != null) | .message.content[] | select(.type == "text") | .text'
    local result

    if [ "$line_limit" -gt 0 ]; then
        if ! result=$(tail -n "$line_limit" "$transcript_path" | jq -r "$jq_filter_base" | tail -n 1); then
            echo "Error: Failed to parse transcript JSON from '$transcript_path'" >&2
            return 1
        fi
    else
        if [ "$full_content" = "true" ]; then
            # Get all text content from the last assistant message, concatenated
            if ! result=$(jq -r '
                map(select(.type == "assistant")) |
                if length > 0 then
                    .[-1].message.content |
                    map(select(.type == "text") | .text) |
                    join("")
                else
                    empty
                end
            ' "$transcript_path" 2>/dev/null); then
                echo "Error: Failed to parse transcript JSON from '$transcript_path'" >&2
                return 1
            fi
        else
            # Get the last line of text content from the last assistant message
            # This was the original behavior for no line_limit and full_content=false.
            if ! result=$(jq -r '
                map(select(.type == "assistant")) |
                if length > 0 then
                    .[-1].message.content |
                    map(select(.type == "text") | .text) |
                    join("\n") | # Join with newline to preserve lines, then take last line
                    split("\n") | .[-1]
                else
                    empty
                end
            ' "$transcript_path" 2>/dev/null); then
                echo "Error: Failed to parse transcript JSON from '$transcript_path'" >&2
                return 1
            fi
        fi
    fi

    echo "$result"
}

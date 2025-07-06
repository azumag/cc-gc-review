#!/bin/bash
# Shared utilities for Claude Code review scripts

set -euo pipefail

# Function to extract last assistant message from JSONL transcript
extract_last_assistant_message() {
    local transcript_path="$1"
    local line_limit="${2:-0}" # 0 means no limit

    if [ ! -f "$transcript_path" ]; then
        echo "Error: Transcript file not found: '$transcript_path'" >&2
        return 1
    fi

    local jq_filter='.[] | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text'
    local result
    
    if [ "$line_limit" -gt 0 ]; then
        if ! result=$(tail -n "$line_limit" "$transcript_path" | jq -r "$jq_filter" | tail -n 1); then
            echo "Error: Failed to parse transcript JSON from '$transcript_path'" >&2
            return 1
        fi
    else
        if ! result=$(jq -r "$jq_filter" "$transcript_path" | tail -n 1); then
            echo "Error: Failed to parse transcript JSON from '$transcript_path'" >&2
            return 1
        fi
    fi
    
    echo "$result"
}

#!/bin/bash

# Debug script to test content extraction from Claude Code transcript

set -euo pipefail

TRANSCRIPT_PATH="/Users/azumag/.claude/projects/-Users-azumag-work-cc-gc-review/11641804-e30a-4198-aacd-3a782a79c64a.jsonl"

echo "================================================================="
echo "DEBUGGING: Content extraction from Claude Code transcript"
echo "================================================================="
echo "Transcript: $TRANSCRIPT_PATH"
echo "File exists: $([ -f "$TRANSCRIPT_PATH" ] && echo "YES" || echo "NO")"
echo "File size: $([ -f "$TRANSCRIPT_PATH" ] && du -h "$TRANSCRIPT_PATH" | cut -f1 || echo "0")"
echo

# Test 1: What does the broken extract_last_assistant_message function do?
echo "TEST 1: Current extract_last_assistant_message function"
echo "========================================================="
echo

source hooks/shared-utils.sh || echo "Failed to source shared-utils.sh"

echo "1.1 Testing with full_content=false (should work):"
echo "---------------------------------------------------"
result1=$(extract_last_assistant_message "$TRANSCRIPT_PATH" 0 false 2>&1 || echo "ERROR")
echo "Result: '$result1'"
echo "Length: ${#result1}"
echo

echo "1.2 Testing with full_content=true (currently broken):"
echo "------------------------------------------------------"
result2=$(extract_last_assistant_message "$TRANSCRIPT_PATH" 0 true 2>&1 || echo "ERROR")
echo "Result: '$result2'"
echo "Length: ${#result2}"
echo

echo "1.3 Testing with line_limit=20 (should work):"
echo "----------------------------------------------"
result3=$(extract_last_assistant_message "$TRANSCRIPT_PATH" 20 false 2>&1 || echo "ERROR")
echo "Result: '$result3'"
echo "Length: ${#result3}"
echo

# Test 2: What does the get_work_summary function return?
echo "TEST 2: get_work_summary function"
echo "=================================="
echo

# Define get_work_summary function to avoid sourcing notification.sh
get_work_summary() {
    local transcript_path="$1"
    local summary=""
    
    if [ -f "$transcript_path" ]; then
        summary=$(extract_last_assistant_message "$transcript_path" 0 true 2>&1 || echo "")
        
        # If still empty, provide a generic fallback
        if [ -z "$summary" ]; then
            summary="Work completed in project $(basename $(pwd))"
        fi
    fi
    
    echo "$summary"
}

work_summary=$(get_work_summary "$TRANSCRIPT_PATH")
echo "Work summary result: '$work_summary'"
echo "Length: ${#work_summary}"
echo

# Test 3: What should the correct implementation look like?
echo "TEST 3: Correct implementation for JSONL files"
echo "==============================================="
echo

echo "3.1 Getting last assistant message UUID:"
echo "----------------------------------------"
last_assistant_uuid=$(cat "$TRANSCRIPT_PATH" | jq -r 'select(.type == "assistant") | .uuid' | tail -1)
echo "Last assistant UUID: $last_assistant_uuid"
echo

echo "3.2 Getting all text content from last assistant message:"
echo "---------------------------------------------------------"
# Find the last assistant message and get all its text content
last_assistant_content=$(cat "$TRANSCRIPT_PATH" | jq -r --arg uuid "$last_assistant_uuid" '
    select(.type == "assistant" and .uuid == $uuid) | 
    .message.content[]? | 
    select(.type == "text") | 
    .text
' | tr '\n' ' ')

echo "Content preview (first 500 chars): '${last_assistant_content:0:500}...'"
echo "Full content length: ${#last_assistant_content}"
echo

echo "3.3 Alternative approach - get content from last 10 assistant messages:"
echo "----------------------------------------------------------------------"
recent_content=$(cat "$TRANSCRIPT_PATH" | jq -r '
    select(.type == "assistant") | 
    .message.content[]? | 
    select(.type == "text") | 
    .text
' | tail -10 | tr '\n' ' ')

echo "Recent content preview (first 500 chars): '${recent_content:0:500}...'"
echo "Recent content length: ${#recent_content}"
echo

# Test 4: What would a working extract_last_assistant_message function look like?
echo "TEST 4: Fixed extract_last_assistant_message function"
echo "====================================================="
echo

extract_last_assistant_message_fixed() {
    local transcript_path="$1"
    local line_limit="${2:-0}" # 0 means no limit
    local full_content="${3:-false}" # true to get full content, false for last line only

    if [ ! -f "$transcript_path" ]; then
        echo "Error: Transcript file not found: '$transcript_path'" >&2
        return 1
    fi

    local result=""

    if [ "$line_limit" -gt 0 ]; then
        # Get from last N lines
        result=$(tail -n "$line_limit" "$transcript_path" | jq -r '
            select(.type == "assistant") | 
            .message.content[]? | 
            select(.type == "text") | 
            .text
        ' | tail -n 1)
    else
        if [ "$full_content" = "true" ]; then
            # Get ALL text content from the last assistant message
            local last_assistant_uuid=$(cat "$transcript_path" | jq -r 'select(.type == "assistant") | .uuid' | tail -1)
            result=$(cat "$transcript_path" | jq -r --arg uuid "$last_assistant_uuid" '
                select(.type == "assistant" and .uuid == $uuid) | 
                .message.content[]? | 
                select(.type == "text") | 
                .text
            ' | tr '\n' ' ')
        else
            # Get just the last line of text from the last assistant message
            result=$(cat "$transcript_path" | jq -r '
                select(.type == "assistant") | 
                .message.content[]? | 
                select(.type == "text") | 
                .text
            ' | tail -1)
        fi
    fi

    echo "$result"
}

echo "4.1 Testing fixed function with full_content=true:"
echo "--------------------------------------------------"
fixed_result=$(extract_last_assistant_message_fixed "$TRANSCRIPT_PATH" 0 true)
echo "Fixed result preview (first 500 chars): '${fixed_result:0:500}...'"
echo "Fixed result length: ${#fixed_result}"
echo

echo "4.2 Testing fixed function with full_content=false:"
echo "---------------------------------------------------"
fixed_result_false=$(extract_last_assistant_message_fixed "$TRANSCRIPT_PATH" 0 false)
echo "Fixed result (last line): '$fixed_result_false'"
echo "Length: ${#fixed_result_false}"
echo

# Test 5: What does the notification.sh get in the end?
echo "TEST 5: What notification.sh actually gets"
echo "=========================================="
echo

# Simulate what notification.sh does
transcript_path=$(find_transcript_path() {
    local current_dir=$(pwd)
    local claude_projects_dir="$HOME/.claude/projects"
    
    if [ -d "$claude_projects_dir" ]; then
        local escaped_path=$(echo "$current_dir" | sed 's/[^a-zA-Z0-9]/-/g')
        local project_dir=$(find "$claude_projects_dir" -type d -name "*$escaped_path*" | head -1)
        
        if [ -n "$project_dir" ]; then
            local transcript_file=$(ls -t "$project_dir"/*.jsonl 2>/dev/null | head -1)
            if [ -f "$transcript_file" ]; then
                echo "$transcript_file"
                return 0
            fi
        fi
    fi
    return 1
}; find_transcript_path)

echo "Found transcript path: $transcript_path"
echo "Path matches expected: $([ "$transcript_path" = "$TRANSCRIPT_PATH" ] && echo "YES" || echo "NO")"

# Get what notification.sh would get
notification_work_summary=$(get_work_summary "$transcript_path")
echo "Notification work summary: '$notification_work_summary'"
echo "Is empty: $([ -z "$notification_work_summary" ] && echo "YES" || echo "NO")"

# Test the fixed version
get_work_summary_fixed() {
    local transcript_path="$1"
    local summary=""
    
    if [ -f "$transcript_path" ]; then
        summary=$(extract_last_assistant_message_fixed "$transcript_path" 0 true)
        
        # If still empty, provide a generic fallback
        if [ -z "$summary" ]; then
            summary="Work completed in project $(basename $(pwd))"
        fi
    fi
    
    echo "$summary"
}

notification_work_summary_fixed=$(get_work_summary_fixed "$transcript_path")
echo "Fixed notification work summary preview (first 500 chars): '${notification_work_summary_fixed:0:500}...'"
echo "Fixed is empty: $([ -z "$notification_work_summary_fixed" ] && echo "YES" || echo "NO")"

echo
echo "================================================================="
echo "SUMMARY: Why work summaries are empty"
echo "================================================================="
echo
echo "ROOT CAUSE: The extract_last_assistant_message function in shared-utils.sh"
echo "uses jq filters that assume the transcript file contains a JSON array,"
echo "but JSONL files contain individual JSON objects on separate lines."
echo
echo "CURRENT BEHAVIOR:"
echo "- full_content=true: FAILS with jq parse error"
echo "- full_content=false: FAILS with jq parse error"  
echo "- line_limit > 0: WORKS but only gets last line from recent messages"
echo
echo "WHAT notification.sh GETS:"
echo "- Work summary: '$notification_work_summary'"
echo "- Is empty: $([ -z "$notification_work_summary" ] && echo "YES" || echo "NO")"
echo
echo "WHAT notification.sh SHOULD GET:"
echo "- Work summary length: ${#notification_work_summary_fixed} characters"
echo "- Contains actual content: $([ ${#notification_work_summary_fixed} -gt 100 ] && echo "YES" || echo "NO")"
echo
echo "SOLUTION: Fix the jq filters in extract_last_assistant_message function"
echo "to properly handle JSONL format (one JSON object per line)."
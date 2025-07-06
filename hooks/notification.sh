#!/bin/bash
# Discord notification script for Claude Code task completion

set -euo pipefail

# Source shared utilities
source "$(dirname "$0")/shared-utils.sh"

# Load environment variables from .env file
load_env() {
    if [ -f ".env" ]; then
        # Load .env file, ignoring comments and empty lines
        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$line" ]] && continue
            
            # Export variable if it's in KEY=VALUE format
            if [[ "$line" =~ ^[[:space:]]*([[:alnum:]_]+)=(.*)$ ]]; then
                export "${BASH_REMATCH[1]}"="${BASH_REMATCH[2]}"
            fi
        done < ".env"
    fi
}

# Find Claude Code transcript for current project
find_transcript_path() {
    local current_dir=$(pwd)
    local project_name=$(basename "$current_dir")
    
    # Search for transcript files in Claude projects directory
    local claude_projects_dir="$HOME/.claude/projects"
    
    if [ -d "$claude_projects_dir" ]; then
        # Look for project directory containing current path
        local escaped_path=$(echo "$current_dir" | sed 's/[^a-zA-Z0-9]/-/g')
        local project_dir=$(find "$claude_projects_dir" -type d -name "*$escaped_path*" | head -1)
        
        if [ -n "$project_dir" ]; then
            # Find the most recent transcript file in the project directory
            local transcript_file=$(ls -t "$project_dir"/*.jsonl 2>/dev/null | head -1)
            if [ -f "$transcript_file" ]; then
                echo "$transcript_file"
                return 0
            fi
        fi
        
        # Fallback: find the most recent transcript file across all projects
        local recent_transcript=$(find "$claude_projects_dir" -name "*.jsonl" -type f -exec ls -t {} + 2>/dev/null | head -1)
        if [ -f "$recent_transcript" ]; then
            echo "$recent_transcript"
            return 0
        fi
    fi
    
    return 1
}

# Extract task title from work summary
extract_task_title() {
    local summary="$1"
    
    if [ -z "$summary" ]; then
        echo "Task Completed"
        return
    fi
    
    # Look for action words and extract the main task
    local title=""
    
    # Try to extract key action phrases
    if echo "$summary" | grep -q -i "fix\|修正\|解決"; then
        title=$(echo "$summary" | grep -o -i "[^.]*fix[^.]*\|[^.]*修正[^.]*\|[^.]*解決[^.]*" | head -1 | head -c 50)
    elif echo "$summary" | grep -q -i "add\|追加\|実装\|implement"; then
        title=$(echo "$summary" | grep -o -i "[^.]*add[^.]*\|[^.]*追加[^.]*\|[^.]*実装[^.]*\|[^.]*implement[^.]*" | head -1 | head -c 50)
    elif echo "$summary" | grep -q -i "refactor\|improve\|update\|リファクタ\|改善\|更新"; then
        title=$(echo "$summary" | grep -o -i "[^.]*refactor[^.]*\|[^.]*improve[^.]*\|[^.]*update[^.]*\|[^.]*リファクタ[^.]*\|[^.]*改善[^.]*\|[^.]*更新[^.]*" | head -1 | head -c 50)
    else
        # Fallback: extract first meaningful sentence or phrase
        title=$(echo "$summary" | sed 's/[.!?].*//' | head -c 50)
    fi
    
    # Clean up and format title
    title=$(echo "$title" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]\+/ /g')
    
    # Remove bullet points and common prefixes
    title=$(echo "$title" | sed -e 's/^[•*-][[:space:]]*//' -e 's/^Step [0-9]*[:.][[:space:]]*//')
    
    # Add ellipsis if truncated
    if [ ${#title} -lt ${#summary} ] && [ ${#title} -gt 40 ]; then
        title="${title}..."
    fi
    
    # Fallback if title is too short or empty
    if [ ${#title} -lt 10 ]; then
        title="Code Changes Completed"
    fi
    
    echo "$title"
}

# Get comprehensive work summary from Claude Code transcript
get_work_summary() {
    local transcript_path="$1"
    local summary=""
    
    if [ -f "$transcript_path" ]; then
        # Get recent assistant messages (not just the last one)
        local jq_filter='select(.type == "assistant" and .message.content != null) | .message.content[] | select(.type == "text") | .text'
        
        # Extract last 3 assistant messages to get more comprehensive summary
        local recent_messages=$(tail -n 50 "$transcript_path" | jq -r "$jq_filter" 2>/dev/null | tail -n 3)
        
        if [ -n "$recent_messages" ]; then
            # Combine recent messages with newlines, focusing on substantive content
            summary=$(echo "$recent_messages" | grep -v "^$" | head -c 800)
            
            # If we got multiple messages, format them nicely
            if [ $(echo "$recent_messages" | wc -l) -gt 1 ]; then
                summary=$(echo "$recent_messages" | tail -n 2 | sed 's/^/• /' | tr '\n' ' ')
            fi
        fi
        
        # Fallback to single last message if multiple messages didn't work well
        if [ -z "$summary" ] || [ ${#summary} -lt 50 ]; then
            summary=$(extract_last_assistant_message "$transcript_path" 0)
        fi
        
        # Limit summary to 1000 characters to avoid Discord message limits
        if [ ${#summary} -gt 1000 ]; then
            if [ ${#summary} -gt 800 ]; then
                local first_part=$(echo "$summary" | head -c 400)
                local last_part=$(echo "$summary" | tail -c 400)
                summary="${first_part}...(中略)...${last_part}"
            else
                summary=$(echo "$summary" | head -c 1000)
                summary="${summary}...(truncated)"
            fi
        fi
    fi
    
    echo "$summary"
}

# Create Discord notification payload
create_discord_payload() {
    local branch="$1"
    local repo_name="$2"
    local work_summary="$3"
    local task_title="$4"
    
    # Escape JSON values properly
    local branch_json=$(echo -n "$branch" | jq -R -s '.')
    local repo_json=$(echo -n "$repo_name" | jq -R -s '.')
    local summary_json=$(echo -n "$work_summary" | jq -R -s '.')
    local title_json=$(echo -n "$task_title" | jq -R -s '.')
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
    
    cat <<EOF
{
  "content": "🎉 **${task_title}** 🎉",
  "embeds": [
    {
      "title": ${title_json},
      "color": 5763719,
      "fields": [
        {
          "name": "Repository",
          "value": ${repo_json},
          "inline": true
        },
        {
          "name": "Branch",
          "value": ${branch_json},
          "inline": true
        },
        {
          "name": "Work Summary",
          "value": ${summary_json},
          "inline": false
        }
      ],
      "footer": {
        "text": "Claude Code"
      },
      "timestamp": "${timestamp}"
    }
  ]
}
EOF
}

# Send Discord notification
send_discord_notification() {
    local webhook_url="$1"
    local payload="$2"
    
    if curl -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --fail \
        --silent \
        --show-error \
        "$webhook_url"; then
        echo "✅ Discord notification sent successfully"
        return 0
    else
        echo "❌ Failed to send Discord notification" >&2
        return 1
    fi
}

# Main execution
main() {
    # Load environment variables
    load_env
    
    # Get input from Claude Code stop hook if available
    local input=""
    if [ -t 0 ]; then
        # Running manually (no piped input)
        input=""
    else
        # Running from Claude Code stop hook
        input=$(cat)
    fi
    
    # Get branch name
    local branch
    if [ -z "${1:-}" ]; then
        branch=$(git branch --show-current)
    else
        branch="$1"
    fi
    
    # Get repository name
    local repo_name
    repo_name=$(basename -s .git "$(git config --get remote.origin.url)")
    
    # Get work summary from Claude Code transcript if available
    local work_summary=""
    local transcript_path="${CLAUDE_TRANSCRIPT_PATH:-}"
    
    # Extract transcript path from stop hook input if available
    if [ -n "$input" ]; then
        transcript_path=$(echo "$input" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")
    fi
    
    # Try to find transcript automatically if not provided
    if [ -z "$transcript_path" ]; then
        transcript_path=$(find_transcript_path)
    fi
    
    if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
        work_summary=$(get_work_summary "$transcript_path")
    fi
    
    # Fallback to generic message if no summary available
    if [ -z "$work_summary" ]; then
        work_summary="Task completed successfully"
    fi
    
    # Extract task title from work summary
    local task_title=$(extract_task_title "$work_summary")
    
    # Check if Discord webhook URL is configured
    if [ -n "${DISCORD_CLAUDE_NOTIFICATION_WEBHOOK_URL:-}" ]; then
        # Validate webhook URL
        if [[ ! "$DISCORD_CLAUDE_NOTIFICATION_WEBHOOK_URL" =~ ^https://discord(app)?\.com/api/webhooks/ ]]; then
            echo "❌ Invalid Discord webhook URL" >&2
            exit 1
        fi
        
        # Create and send Discord notification
        local payload
        payload=$(create_discord_payload "$branch" "$repo_name" "$work_summary" "$task_title")
        
        if send_discord_notification "$DISCORD_CLAUDE_NOTIFICATION_WEBHOOK_URL" "$payload"; then
            echo "✅ Discord notification sent for ${repo_name}/${branch}: ${task_title}"
        else
            echo "❌ Failed to send Discord notification for ${repo_name}/${branch}" >&2
            exit 1
        fi
    else
        echo "⚠️  Discord webhook URL not configured in .env file"
        echo "   Add DISCORD_CLAUDE_NOTIFICATION_WEBHOOK_URL to .env to enable Discord notifications"
    fi
    
    # Also send macOS notification if available
    if command -v terminal-notifier >/dev/null 2>&1; then
        terminal-notifier -title "Claude Code" -message "🎉 ${task_title} (${repo_name}/${branch})" -sound Glass
        echo "✅ macOS notification sent: ${task_title} for ${repo_name}/${branch}"
    fi
}

# Execute main function
main "$@"

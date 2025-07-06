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

# Get work summary from Claude Code transcript
get_work_summary() {
    local transcript_path="$1"
    local summary=""
    
    if [ -f "$transcript_path" ]; then
        summary=$(extract_last_assistant_message "$transcript_path" 0)
        
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
    
    # Escape JSON values properly
    local branch_json=$(echo -n "$branch" | jq -R -s '.')
    local repo_json=$(echo -n "$repo_name" | jq -R -s '.')
    local summary_json=$(echo -n "$work_summary" | jq -R -s '.')
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
    
    cat <<EOF
{
  "content": "🎉 **Claude Code Task Completed** 🎉",
  "embeds": [
    {
      "title": "Task Completion Summary",
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
    
    if [ -n "$transcript_path" ]; then
        work_summary=$(get_work_summary "$transcript_path")
    fi
    
    # Fallback to generic message if no summary available
    if [ -z "$work_summary" ]; then
        work_summary="Task completed successfully"
    fi
    
    # Check if Discord webhook URL is configured
    if [ -n "${DISCORD_CLAUDE_NOTIFICATION_WEBHOOK_URL:-}" ]; then
        # Validate webhook URL
        if [[ ! "$DISCORD_CLAUDE_NOTIFICATION_WEBHOOK_URL" =~ ^https://discord(app)?\.com/api/webhooks/ ]]; then
            echo "❌ Invalid Discord webhook URL" >&2
            exit 1
        fi
        
        # Create and send Discord notification
        local payload
        payload=$(create_discord_payload "$branch" "$repo_name" "$work_summary")
        
        if send_discord_notification "$DISCORD_CLAUDE_NOTIFICATION_WEBHOOK_URL" "$payload"; then
            echo "✅ Discord notification sent for ${repo_name}/${branch}"
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
        terminal-notifier -title "Claude Code" -message "Task completed🎉 (${repo_name}/${branch})" -sound Glass
        echo "✅ macOS notification sent: Task completed for ${repo_name}/${branch}"
    fi
}

# Execute main function
main "$@"

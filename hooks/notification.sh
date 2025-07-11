#!/bin/bash
# Discord notification script for Claude Code task completion

set -euo pipefail

# Source shared utilities
# Handle both direct execution and sourcing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    source "$(dirname "$0")/shared-utils.sh"
else
    # Script is being sourced - use BASH_SOURCE[0] to get the script's actual location
    source "$(dirname "${BASH_SOURCE[0]}")/shared-utils.sh"
fi

# Load environment variables from .env file
load_env() {
    if [ -f ".env" ]; then
        # Load .env file, ignoring comments and empty lines
        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ $line =~ ^[[:space:]]*# ]] && continue
            [[ -z $line ]] && continue

            # Export variable if it's in KEY=VALUE format
            if [[ $line =~ ^[[:space:]]*([[:alnum:]_]+)=(.*)$ ]]; then
                export "${BASH_REMATCH[1]}"="${BASH_REMATCH[2]}"
            fi
        done <".env"
    fi
}

# Find Claude Code transcript for current project
find_transcript_path() {
    local current_dir
    current_dir=$(pwd)

    # Search for transcript files in Claude projects directory
    local claude_projects_dir="$HOME/.claude/projects"

    if [ -d "$claude_projects_dir" ]; then
        # Look for project directory containing current path
        local escaped_path
        escaped_path=$(echo "$current_dir" | sed 's/[^a-zA-Z0-9]/-/g')
        local project_dir
        project_dir=$(find "$claude_projects_dir" -type d -name "*$escaped_path*" | head -1)

        if [ -n "$project_dir" ]; then
            # Find the most recent transcript file in the project directory
            local transcript_file
            transcript_file=$(ls -t "$project_dir"/*.jsonl 2>/dev/null | head -1)
            if [ -f "$transcript_file" ]; then
                echo "$transcript_file"
                return 0
            fi
        fi

        # Fallback: find the most recent transcript file across all projects
        local recent_transcript
        recent_transcript=$(find "$claude_projects_dir" -name "*.jsonl" -type f -exec ls -t {} + 2>/dev/null | head -1)
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

    # Try multiple strategies to find a meaningful title
    local title=""
    
    # Strategy 1: Look for lines starting with common task indicators
    title=$(echo "$summary" | grep -E "^(fix|add|update|implement|create|remove|refactor|improve|resolve|complete)" -i | head -n 1)
    
    # Strategy 2: Look for lines with task-like patterns (avoid generic headers)
    if [ -z "$title" ] || [ ${#title} -lt 10 ]; then
        title=$(echo "$summary" | grep -v -E "^(##|Work Summary|作業報告|Summary)" | grep -E "^[^a-z]*[A-Z]" | head -n 1)
    fi
    
    # Strategy 3: Get the last non-empty line (original behavior)
    if [ -z "$title" ] || [ ${#title} -lt 5 ]; then
        title=$(echo "$summary" | grep -v "^[[:space:]]*$" | tail -n 1)
    fi
    
    # Strategy 4: Use first substantial line if others fail
    if [ -z "$title" ] || [ ${#title} -lt 5 ]; then
        title=$(echo "$summary" | grep -v -E "^(##|Work Summary|作業報告|Summary|^[[:space:]]*$)" | head -n 1)
    fi

    # Clean up and format title
    title=$(echo "$title" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]\+/ /g')
    title=$(echo "$title" | sed -e 's/^Work Summary:[[:space:]]*//' -e 's/^\*\*Work Summary\*\*:[[:space:]]*//')
    title=$(echo "$title" | sed -e 's/^作業報告:[[:space:]]*//' -e 's/^\*\*作業報告\*\*:[[:space:]]*//')

    # Remove bullet points and common prefixes
    title=$(echo "$title" | sed -e 's/^[•*-][[:space:]]*//' -e 's/^Step [0-9]*[:.][[:space:]]*//' -e 's/^[0-9]*\.[[:space:]]*//')
    
    # Remove markdown formatting
    title=$(echo "$title" | sed -e 's/\*\*//g' -e 's/__//g' -e 's/`//g')

    # Fallback if title is still too short or empty
    if [ -z "$title" ] || [ ${#title} -lt 5 ]; then
        title="Task Completed"
    fi

    echo "$title"
}

# Get complete work summary from Claude Code transcript
get_work_summary() {
    local transcript_path="$1"
    local summary=""

    if [ -f "$transcript_path" ]; then
        summary=$(extract_last_assistant_message "$transcript_path" 0 true)

        # If still empty, provide a generic fallback
        if [ -z "$summary" ]; then
            summary="Work completed in project $(basename "$(pwd)")"
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

    # Create plain text message with all information
    local content_text="🎉 **${task_title}** 🎉

Repository: ${repo_name}
Branch: ${branch}

${work_summary}"

    # Use jq to properly escape the content for JSON
    local content_json=$(echo -n "$content_text" | jq -R -s '.')

    cat <<EOF
{
  "content": ${content_json}
}
EOF
}

# Send Discord notification
send_discord_notification() {
    local webhook_url="$1"
    local payload="$2"

    # Add retry logic for Discord notifications
    local max_retries=3
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
        local curl_output
        local curl_exit_code

        curl_output=$(curl -X POST \
            -H "Content-Type: application/json" \
            -d "$payload" \
            --fail \
            --show-error \
            --max-time 30 \
            "$webhook_url" 2>&1)
        curl_exit_code=$?

        if [ $curl_exit_code -eq 0 ]; then
            echo "✅ Discord notification sent successfully"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                echo "⚠️ Discord notification failed (attempt $retry_count/$max_retries): $curl_output" >&2
                sleep 2
            else
                echo "❌ Discord notification failed after $max_retries attempts. Last error: $curl_output" >&2
            fi
        fi
    done

    return 1
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
        if [[ ! $DISCORD_CLAUDE_NOTIFICATION_WEBHOOK_URL =~ ^https://discord(app)?\.com/api/webhooks/ ]]; then
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
            # Don't exit with error to avoid breaking the stop hook chain
            # Just log the failure and continue
        fi
    else
        echo "⚠️  Discord webhook URL not configured in .env file"
        echo "   Add DISCORD_CLAUDE_NOTIFICATION_WEBHOOK_URL to .env to enable Discord notifications"
    fi

    # Also send macOS notification if available (no duplicate messaging)
    if command -v terminal-notifier >/dev/null 2>&1; then
        terminal-notifier -title "Claude Code" -message "🎉 ${task_title} (${repo_name}/${branch})" -sound Glass
        # Don't echo completion message here to avoid duplication
    fi

    # Always exit successfully to avoid breaking the hook chain
    exit 0
}

# Execute main function only when script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

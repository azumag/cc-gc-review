#!/bin/bash

# Discord notification script for CI failures
# Usage: ./send_discord_notification.sh [webhook_url] [failed_jobs] [branch] [sha] [actor] [commit_message] [run_url]

set -euo pipefail

# Check if all required arguments are provided
if [ $# -ne 7 ]; then
    echo "Error: Missing required arguments"
    echo "Usage: $0 [webhook_url] [failed_jobs] [branch] [sha] [actor] [commit_message] [run_url]"
    exit 1
fi

WEBHOOK_URL="$1"
FAILED_JOBS="$2"
BRANCH="$3"
SHA="$4"
ACTOR="$5"
COMMIT_MESSAGE="$6"
RUN_URL="$7"

# Validate webhook URL
if [[ ! "$WEBHOOK_URL" =~ ^https://discord(app)?\.com/api/webhooks/ ]]; then
    echo "Error: Invalid Discord webhook URL"
    exit 1
fi

# Create JSON payload with proper escaping
create_discord_payload() {
    local json_payload
    json_payload=$(cat <<EOF
{
  "content": "🚨 **CI Build Failed** 🚨",
  "embeds": [
    {
      "title": "Build Failure Details",
      "color": 15158332,
      "fields": [
        {
          "name": "Failed Jobs",
          "value": "${FAILED_JOBS}",
          "inline": true
        },
        {
          "name": "Branch",
          "value": "${BRANCH}",
          "inline": true
        },
        {
          "name": "Commit",
          "value": "\`${SHA:0:7}\`",
          "inline": true
        },
        {
          "name": "Author",
          "value": "${ACTOR}",
          "inline": true
        },
        {
          "name": "Commit Message",
          "value": "${COMMIT_MESSAGE}",
          "inline": false
        }
      ],
      "footer": {
        "text": "GitHub Actions"
      },
      "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
    }
  ],
  "components": [
    {
      "type": 1,
      "components": [
        {
          "type": 2,
          "style": 5,
          "label": "View Build",
          "url": "${RUN_URL}"
        }
      ]
    }
  ]
}
EOF
    )
    echo "$json_payload"
}

# Send notification to Discord with error handling
send_notification() {
    local payload
    payload=$(create_discord_payload)
    
    echo "Sending Discord notification..."
    
    if curl -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --fail \
        --silent \
        --show-error \
        "$WEBHOOK_URL"; then
        echo "✅ Discord notification sent successfully"
        return 0
    else
        echo "❌ Failed to send Discord notification"
        return 1
    fi
}

# Main execution
main() {
    echo "=== Discord Notification Script ==="
    echo "Branch: $BRANCH"
    echo "Failed Jobs: $FAILED_JOBS"
    echo "Commit: ${SHA:0:7}"
    echo "Author: $ACTOR"
    echo "=================================="
    
    if send_notification; then
        echo "Notification process completed successfully"
        exit 0
    else
        echo "Notification process failed"
        exit 1
    fi
}

# Execute main function
main "$@"
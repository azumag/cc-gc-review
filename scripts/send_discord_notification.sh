#!/bin/bash

# Discord notification script for CI failures
# Usage: ./send_discord_notification.sh [webhook_url] [test_result] [lint_result] [format_result] [integration_result] [release_result] [branch] [sha] [actor] [commit_message] [run_url]

set -euo pipefail

# Check if all required arguments are provided
if [ $# -ne 11 ]; then
    echo "Error: Missing required arguments"
    echo "Usage: $0 [webhook_url] [test_result] [lint_result] [format_result] [integration_result] [release_result] [branch] [sha] [actor] [commit_message] [run_url]"
    exit 1
fi

WEBHOOK_URL="$1"
TEST_RESULT="$2"
LINT_RESULT="$3"
FORMAT_RESULT="$4"
INTEGRATION_RESULT="$5"
RELEASE_RESULT="$6"
BRANCH="$7"
SHA="$8"
ACTOR="$9"
COMMIT_MESSAGE="${10}"
RUN_URL="${11}"

# Validate webhook URL
if [[ ! "$WEBHOOK_URL" =~ ^https://discord(app)?\.com/api/webhooks/ ]]; then
    echo "Error: Invalid Discord webhook URL"
    exit 1
fi

# Collect failed jobs information
FAILED_JOBS=""
if [[ "$TEST_RESULT" == "failure" ]]; then
  FAILED_JOBS="${FAILED_JOBS}• Test Suite\n"
fi
if [[ "$LINT_RESULT" == "failure" ]]; then
  FAILED_JOBS="${FAILED_JOBS}• Linting\n"
fi
if [[ "$FORMAT_RESULT" == "failure" ]]; then
  FAILED_JOBS="${FAILED_JOBS}• Formatting\n"
fi
if [[ "$INTEGRATION_RESULT" == "failure" ]]; then
  FAILED_JOBS="${FAILED_JOBS}• Integration Tests\n"
fi
if [[ "$RELEASE_RESULT" == "failure" ]]; then
  FAILED_JOBS="${FAILED_JOBS}• Release Process\n"
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
          "value": "$(echo "${FAILED_JOBS}" | jq -R -s '.')",
          "inline": true
        },
        {
          "name": "Branch",
          "value": "$(echo "${BRANCH}" | jq -R -s '.')",
          "inline": true
        },
        {
          "name": "Commit",
          "value": "`$(echo "${SHA:0:7}" | jq -R -s '.')`",
          "inline": true
        },
        {
          "name": "Author",
          "value": "$(echo "${ACTOR}" | jq -R -s '.')",
          "inline": true
        },
        {
          "name": "Commit Message",
          "value": "$(echo "${COMMIT_MESSAGE}" | jq -R -s '.')",
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
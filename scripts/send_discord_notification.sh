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
    # Properly escape JSON values
    local failed_jobs_json=$(echo -n "${FAILED_JOBS}" | jq -R -s '.')
    local branch_json=$(echo -n "${BRANCH}" | jq -R -s '.')
    local commit_short="${SHA:0:7}"
    local commit_json=$(echo -n "${commit_short}" | jq -R -s '.')
    local actor_json=$(echo -n "${ACTOR}" | jq -R -s '.')
    local message_json=$(echo -n "${COMMIT_MESSAGE}" | jq -R -s '.')
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
    
    cat <<EOF
{
  "content": "🚨 **CI Build Failed** 🚨",
  "embeds": [
    {
      "title": "Build Failure Details",
      "color": 15158332,
      "fields": [
        {
          "name": "Failed Jobs",
          "value": ${failed_jobs_json},
          "inline": true
        },
        {
          "name": "Branch",
          "value": ${branch_json},
          "inline": true
        },
        {
          "name": "Commit",
          "value": ${commit_json},
          "inline": true
        },
        {
          "name": "Author",
          "value": ${actor_json},
          "inline": true
        },
        {
          "name": "Commit Message",
          "value": ${message_json},
          "inline": false
        }
      ],
      "footer": {
        "text": "GitHub Actions"
      },
      "timestamp": "${timestamp}"
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
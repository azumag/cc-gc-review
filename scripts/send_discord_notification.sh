#!/bin/bash

# Discord notification script for CI failures
# Usage: ./send_discord_notification.sh [webhook_url] [test_result] [lint_result] [format_result] [integration_result] [release_result] [branch] [sha] [actor] [commit_message] [run_url]

set -euo pipefail

# Check if all required arguments are provided
if [ $# -ne 11 ]; then
    printf "Error: Missing required arguments\n"
    printf "Usage: %s [webhook_url] [test_result] [lint_result] [format_result] [integration_result] [release_result] [branch] [sha] [actor] [commit_message] [run_url]\n" "$0"
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
    printf "Error: Invalid Discord webhook URL\n"
    exit 1
fi

# Collect failed jobs information using arrays for clean, DRY code
declare -a failed_jobs_array=()
declare -a job_results=("$TEST_RESULT" "$LINT_RESULT" "$FORMAT_RESULT" "$INTEGRATION_RESULT" "$RELEASE_RESULT")
declare -a job_names=("Test Suite" "Linting" "Formatting" "Integration Tests" "Release Process")

for i in "${!job_results[@]}"; do
    if [[ "${job_results[$i]}" == "failure" ]]; then
        failed_jobs_array+=("• ${job_names[$i]}")
    fi
done

# Join array elements with newlines using printf
FAILED_JOBS=""
if [[ ${#failed_jobs_array[@]} -gt 0 ]]; then
    FAILED_JOBS=$(printf "%s\\n" "${failed_jobs_array[@]}")
    # Remove trailing newline
    FAILED_JOBS="${FAILED_JOBS%\\n}"
fi

# Create JSON payload with proper escaping
create_discord_payload() {
    # Properly escape JSON values
    # Convert literal \n to actual newlines for proper JSON encoding
    local failed_jobs_formatted=$(echo -e "${FAILED_JOBS}")
    local failed_jobs_json=$(echo -n "${failed_jobs_formatted}" | jq -R -s '.')
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
    
    printf "Sending Discord notification...\n"
    
    if curl -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --fail \
        --silent \
        --show-error \
        "$WEBHOOK_URL"; then
        printf "✅ Discord notification sent successfully\n"
        return 0
    else
        printf "❌ Failed to send Discord notification\n"
        return 1
    fi
}

# Main execution
main() {
    printf "=== Discord Notification Script ===\n"
    printf "Branch: %s\n" "$BRANCH"
    printf "Failed Jobs:\n%s\n" "$FAILED_JOBS"
    printf "Commit: %s\n" "${SHA:0:7}"
    printf "Author: %s\n" "$ACTOR"
    printf "==================================\n"
    
    if send_notification; then
        printf "Notification process completed successfully\n"
        exit 0
    else
        printf "Notification process failed\n"
        exit 1
    fi
}

# Execute main function
main "$@"
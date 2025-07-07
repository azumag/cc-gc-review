#!/bin/bash

# Discord notification script for CI failures
# Usage: ./send_discord_notification.sh [webhook_url] [test_result] [lint_result] [format_result] [integration_result] [release_result] [branch] [sha] [actor] [commit_message] [run_url]

set -euo pipefail

# Check if all required arguments are provided
if [ $# -ne 11 ]; then
    printf "Error: Missing required arguments\n" >&2
    printf "Usage: %s [webhook_url] [test_result] [lint_result] [format_result] [integration_result] [release_result] [branch] [sha] [actor] [commit_message] [run_url]\n" "$0" >&2
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
    printf "Error: Invalid Discord webhook URL\n" >&2
    exit 1
fi

# Function to collect failed jobs with proper encapsulation
collect_failed_jobs() {
    local -a job_results=("$@")
    local -a job_names=("Test Suite" "Linting" "Formatting" "Integration Tests" "Release Process")
    local -a failed_jobs_array=()

    for i in "${!job_results[@]}"; do
        if [[ "${job_results[$i]}" == "failure" ]]; then
            failed_jobs_array+=("• ${job_names[$i]}")
        fi
    done

    # Join array elements with newlines using IFS manipulation in a subshell
    local failed_jobs=""
    if [[ ${#failed_jobs_array[@]} -gt 0 ]]; then
        # Use a subshell to avoid affecting global IFS
        failed_jobs=$(
            local IFS=$'\n'
            echo -n "${failed_jobs_array[*]}"
        )
    fi

    echo -n "$failed_jobs"
}

# Collect failed jobs information
FAILED_JOBS=$(collect_failed_jobs "$TEST_RESULT" "$LINT_RESULT" "$FORMAT_RESULT" "$INTEGRATION_RESULT" "$RELEASE_RESULT")

# Create JSON payload with proper escaping
create_discord_payload() {
    # Properly escape JSON values
    # FAILED_JOBS already contains proper newlines from collect_failed_jobs
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
        printf "❌ Failed to send Discord notification\n" >&2
        return 1
    fi
}

# Main execution
main() {
    printf "=== Discord Notification Script ===\n"
    printf "Branch: %s\n" "$BRANCH"
    if [[ -n "$FAILED_JOBS" ]]; then
        printf "Failed Jobs:\n%s\n" "$FAILED_JOBS"
    else
        printf "Failed Jobs: None\n"
    fi
    printf "Commit: %s\n" "${SHA:0:7}"
    printf "Author: %s\n" "$ACTOR"
    printf "==================================\n"

    if send_notification; then
        printf "Notification process completed successfully\n"
        exit 0
    else
        printf "Notification process failed\n" >&2
        exit 1
    fi
}

# Execute main function
main "$@"

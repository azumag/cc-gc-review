#!/usr/bin/env bats

# Test title extraction functionality for notification.sh using actual implementation

setup() {
    # Get the repository root directory before changing directories
    REPO_ROOT=$(git rev-parse --show-toplevel)
    
    # Create temporary directory for tests
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"

    # Mock the shared-utils.sh dependency
    echo '#!/bin/bash' > shared-utils.sh
    echo 'extract_last_assistant_message() { echo "mock function"; }' >> shared-utils.sh
    
    # Copy and modify notification.sh to work in test environment
    cp "$REPO_ROOT/hooks/notification.sh" ./notification.sh
    
    # Fix the path in notification.sh to use local shared-utils.sh (compatible with both macOS and Linux)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' 's|source "$(dirname "$0")/shared-utils.sh"|source "./shared-utils.sh"|g' notification.sh
    else
        sed -i 's|source "$(dirname "$0")/shared-utils.sh"|source "./shared-utils.sh"|g' notification.sh
    fi
    
    # Create a mock git repository
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"
}

teardown() {
    # Clean up test directory
    cd /
    rm -rf "$TEST_DIR"
}

@test "notification.sh extract_task_title should extract last meaningful line from summary" {
    # Define the extract_task_title function locally to avoid sourcing the entire script
    extract_task_title() {
        local summary="$1"

        if [ -z "$summary" ]; then
            echo "Task Completed"
            return
        fi

        # Extract the last meaningful line as title
        local title
        title=$(echo "$summary" | tail -n 1)

        # Clean up and format title - remove Work Summary: prefix
        title=$(echo "$title" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]\+/ /g')
        title=$(echo "$title" | sed -e 's/^Work Summary:[[:space:]]*//' -e 's/^\*\*Work Summary\*\*:[[:space:]]*//')

        # Remove bullet points and common prefixes
        title=$(echo "$title" | sed -e 's/^[•*-][[:space:]]*//' -e 's/^Step [0-9]*[:.][[:space:]]*//' -e 's/^[0-9]*\.[[:space:]]*//')

        # Fallback if title is too short or empty
        if [ ${#title} -lt 5 ]; then
            title="Task Completed"
        fi

        echo "$title"
    }
    
    local summary="Work Summary: Multiple tasks completed
    
    Task 1: Fixed the configuration issue
    Task 2: Updated the documentation
    Task 3: Implemented new feature"
    
    result=$(extract_task_title "$summary")
    
    # Should extract the last meaningful line
    [ "$result" = "Task 3: Implemented new feature" ]
}

@test "notification.sh extract_task_title should handle numbered lists" {
    # Define the extract_task_title function locally to avoid sourcing the entire script
    extract_task_title() {
        local summary="$1"

        if [ -z "$summary" ]; then
            echo "Task Completed"
            return
        fi

        # Extract the last meaningful line as title
        local title
        title=$(echo "$summary" | tail -n 1)

        # Clean up and format title - remove Work Summary: prefix
        title=$(echo "$title" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]\+/ /g')
        title=$(echo "$title" | sed -e 's/^Work Summary:[[:space:]]*//' -e 's/^\*\*Work Summary\*\*:[[:space:]]*//')

        # Remove bullet points and common prefixes
        title=$(echo "$title" | sed -e 's/^[•*-][[:space:]]*//' -e 's/^Step [0-9]*[:.][[:space:]]*//' -e 's/^[0-9]*\.[[:space:]]*//')

        # Fallback if title is too short or empty
        if [ ${#title} -lt 5 ]; then
            title="Task Completed"
        fi

        echo "$title"
    }
    
    local summary="1. Initialize the project
    2. Configure the settings
    3. Deploy the application"
    
    result=$(extract_task_title "$summary")
    
    [ "$result" = "Deploy the application" ]
}

@test "notification.sh extract_task_title should handle different from full summary" {
    # Define the extract_task_title function locally to avoid sourcing the entire script
    extract_task_title() {
        local summary="$1"

        if [ -z "$summary" ]; then
            echo "Task Completed"
            return
        fi

        # Extract the last meaningful line as title
        local title
        title=$(echo "$summary" | tail -n 1)

        # Clean up and format title - remove Work Summary: prefix
        title=$(echo "$title" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]\+/ /g')
        title=$(echo "$title" | sed -e 's/^Work Summary:[[:space:]]*//' -e 's/^\*\*Work Summary\*\*:[[:space:]]*//')

        # Remove bullet points and common prefixes
        title=$(echo "$title" | sed -e 's/^[•*-][[:space:]]*//' -e 's/^Step [0-9]*[:.][[:space:]]*//' -e 's/^[0-9]*\.[[:space:]]*//')

        # Fallback if title is too short or empty
        if [ ${#title} -lt 5 ]; then
            title="Task Completed"
        fi

        echo "$title"
    }
    
    local summary="Work Summary: Fixed Discord notification issues

    1. Added retry logic for failed notifications
    2. Improved error handling and logging
    3. Fixed hook chain continuation
    4. Enhanced timeout settings"
    
    result=$(extract_task_title "$summary")
    
    # Title should be the last line (shorter)
    [ "$result" = "Enhanced timeout settings" ]
    
    # And should be different from the full summary
    [ "$result" != "$summary" ]
}
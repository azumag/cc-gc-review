#!/usr/bin/env bats

# Test title extraction functionality for notification.sh using actual implementation

setup() {
    # Create temporary directory for tests
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
    
    # Mock the shared-utils.sh dependency
    mkdir -p hooks
    echo '#!/bin/bash' > hooks/shared-utils.sh
    echo 'extract_last_assistant_message() { echo "mock function"; }' >> hooks/shared-utils.sh
    
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
    source "/Users/azumag/work/cc-gc-review/hooks/notification.sh"
    
    local summary="Work Summary: Multiple tasks completed
    
    Task 1: Fixed the configuration issue
    Task 2: Updated the documentation
    Task 3: Implemented new feature"
    
    result=$(extract_task_title "$summary")
    
    # Should extract the last meaningful line
    [ "$result" = "Task 3: Implemented new feature" ]
}

@test "notification.sh extract_task_title should handle numbered lists" {
    source "/Users/azumag/work/cc-gc-review/hooks/notification.sh"
    
    local summary="1. Initialize the project
    2. Configure the settings
    3. Deploy the application"
    
    result=$(extract_task_title "$summary")
    
    [ "$result" = "Deploy the application" ]
}

@test "notification.sh extract_task_title should handle different from full summary" {
    source "/Users/azumag/work/cc-gc-review/hooks/notification.sh"
    
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
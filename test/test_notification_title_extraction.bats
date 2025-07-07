#!/usr/bin/env bats

# Test title extraction functionality for notification.sh

setup() {
    # Create temporary directory for tests
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
    
    # Copy just the functions we need to test
    # Define the extract_task_title function locally
    extract_task_title() {
        local summary="$1"
        
        if [ -z "$summary" ]; then
            echo "Task Completed"
            return
        fi
        
        # Extract the last meaningful line as title
        local title=$(echo "$summary" | grep -v "^$" | tail -n 1)
        
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

@test "extract_task_title should extract last meaningful line from summary" {
    local summary="Work Summary: Multiple tasks completed
    
    Task 1: Fixed the configuration issue
    Task 2: Updated the documentation
    Task 3: Implemented new feature"
    
    result=$(extract_task_title "$summary")
    
    # Should extract the last meaningful line
    [ "$result" = "Task 3: Implemented new feature" ]
}

@test "extract_task_title should handle single line summary" {
    local summary="Fixed Discord notification bug"
    
    result=$(extract_task_title "$summary")
    
    [ "$result" = "Fixed Discord notification bug" ]
}

@test "extract_task_title should remove Work Summary prefix" {
    local summary="Work Summary: Updated the notification system"
    
    result=$(extract_task_title "$summary")
    
    [ "$result" = "Updated the notification system" ]
}

@test "extract_task_title should remove bullet points and prefixes" {
    local summary="• Fixed the notification issue
    - Updated error handling
    * Improved logging"
    
    result=$(extract_task_title "$summary")
    
    [ "$result" = "Improved logging" ]
}

@test "extract_task_title should handle empty summary" {
    local summary=""
    
    result=$(extract_task_title "$summary")
    
    [ "$result" = "Task Completed" ]
}

@test "extract_task_title should handle summary with only whitespace" {
    local summary="   
    
    "
    
    result=$(extract_task_title "$summary")
    
    [ "$result" = "Task Completed" ]
}

@test "extract_task_title should handle Step prefixes" {
    local summary="Step 1: Initialize the project
    Step 2: Configure the settings
    Step 3: Deploy the application"
    
    result=$(extract_task_title "$summary")
    
    [ "$result" = "Deploy the application" ]
}

@test "extract_task_title should handle numbered lists" {
    local summary="1. Initialize the project
    2. Configure the settings
    3. Deploy the application"
    
    result=$(extract_task_title "$summary")
    
    [ "$result" = "Deploy the application" ]
}

@test "extract_task_title should handle very short titles" {
    local summary="Done"
    
    result=$(extract_task_title "$summary")
    
    [ "$result" = "Task Completed" ]
}

@test "extract_task_title should clean up whitespace" {
    local summary="   Task completed successfully   "
    
    result=$(extract_task_title "$summary")
    
    [ "$result" = "Task completed successfully" ]
}

@test "extract_task_title should handle markdown formatting" {
    local summary="**Work Summary**: Updated the notification system
    
    1. Fixed the Discord webhook
    2. Improved error handling
    3. Added retry logic"
    
    result=$(extract_task_title "$summary")
    
    [ "$result" = "Added retry logic" ]
}
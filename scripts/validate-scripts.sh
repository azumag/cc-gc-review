#!/bin/bash
# Comprehensive script validation and CI integration checker
# Created to prevent future script path and permission issues

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validation functions
validate_script_structure() {
    echo -e "${YELLOW}Validating script structure...${NC}"
    
    # Check hooks directory structure
    if [ ! -d "hooks" ]; then
        echo -e "${RED}ERROR: hooks/ directory not found${NC}"
        return 1
    fi
    
    # Validate all scripts exist and are executable
    local required_scripts=(
        "hooks/gemini-review-hook.sh"
        "hooks/shared-utils.sh"
        "hooks/notification.sh"
        "hooks/ci-monitor-hook.sh"
        "hooks/push-review-complete.sh"
    )
    
    for script in "${required_scripts[@]}"; do
        if [ ! -f "$script" ]; then
            echo -e "${RED}ERROR: Required script missing: $script${NC}"
            return 1
        fi
        if [ ! -x "$script" ]; then
            echo -e "${RED}ERROR: Script not executable: $script${NC}"
            return 1
        fi
    done
    
    echo -e "${GREEN}✓ Script structure validation passed${NC}"
}

validate_json_schema_compliance() {
    echo -e "${YELLOW}Validating JSON schema compliance...${NC}"
    
    # Test JSON output format for gemini-review-hook.sh
    local test_input='{"transcript_path": "/dev/null"}'
    local hook_output
    
    # Create minimal test transcript
    local temp_transcript=$(mktemp)
    echo '{"type": "assistant", "message": {"content": [{"type": "text", "text": "REVIEW_COMPLETED"}]}}' > "$temp_transcript"
    
    # Test hook output
    hook_output=$(echo "{\"transcript_path\": \"$temp_transcript\"}" | ./hooks/gemini-review-hook.sh 2>/dev/null)
    
    # Validate JSON structure
    if ! echo "$hook_output" | jq -e '.decision' >/dev/null 2>&1; then
        echo -e "${RED}ERROR: Hook output missing 'decision' field${NC}"
        rm -f "$temp_transcript"
        return 1
    fi
    
    # Validate decision values
    local decision=$(echo "$hook_output" | jq -r '.decision')
    if [[ "$decision" != "approve" && "$decision" != "block" ]]; then
        echo -e "${RED}ERROR: Invalid decision value: $decision (expected: approve|block)${NC}"
        rm -f "$temp_transcript"
        return 1
    fi
    
    rm -f "$temp_transcript"
    echo -e "${GREEN}✓ JSON schema validation passed${NC}"
}

validate_workflow_consistency() {
    echo -e "${YELLOW}Validating workflow file consistency...${NC}"
    
    # Check for script path references in workflow files
    local workflow_files=(.github/workflows/*.yml .github/workflows/*.yaml)
    local issues_found=0
    
    for workflow in "${workflow_files[@]}"; do
        if [ -f "$workflow" ]; then
            echo "Checking: $workflow"
            
            # Check for problematic patterns
            if grep -q "chmod +x \*\.sh" "$workflow"; then
                echo -e "${RED}ERROR: Found problematic wildcard chmod in $workflow${NC}"
                issues_found=$((issues_found + 1))
            fi
            
            # Check for incorrect script paths
            if grep -q "gemini-review-hook\.sh" "$workflow" && ! grep -q "hooks/gemini-review-hook\.sh" "$workflow"; then
                echo -e "${RED}WARNING: Possible incorrect script path reference in $workflow${NC}"
                issues_found=$((issues_found + 1))
            fi
        fi
    done
    
    if [ $issues_found -eq 0 ]; then
        echo -e "${GREEN}✓ Workflow consistency validation passed${NC}"
    else
        echo -e "${RED}✗ Found $issues_found workflow consistency issues${NC}"
        return 1
    fi
}

# Main execution
main() {
    echo "=== Comprehensive Script Validation ==="
    echo "Project: $(basename "$(pwd)")"
    echo "Date: $(date)"
    echo
    
    validate_script_structure || exit 1
    validate_json_schema_compliance || exit 1
    validate_workflow_consistency || exit 1
    
    echo
    echo -e "${GREEN}✓ All validations passed successfully${NC}"
    echo "Scripts are ready for production use."
}

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
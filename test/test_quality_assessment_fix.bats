#!/usr/bin/env bats

# Test for the quality assessment fix
# This test verifies that the grep -c to grep -o | wc -l fix works correctly
# for counting actual pattern occurrences instead of lines containing patterns

setup() {
    # Load test helpers
    load test_helper
    
    # Test review text with multiple specific references
    export TEST_REVIEW_TEXT="Review of authentication system improvements:
The validateCredentials function needs refactoring, and the processLogin method has security issues.
Changes required in line 42 and line 56.
Also need to modify the handleError function.
Consider adding proper error handling and improved logging."
}

@test "grep -o counts actual pattern occurrences, not lines" {
    # Test the specific reference pattern counting
    old_method=$(echo "$TEST_REVIEW_TEXT" | grep -c "行\|line\|関数\|function\|メソッド" || true)
    new_method=$(echo "$TEST_REVIEW_TEXT" | grep -o "行\|line\|関数\|function\|メソッド" | wc -l)
    
    # The new method should count more occurrences than the old method
    [ "$new_method" -gt "$old_method" ]
    
    # Specifically, we expect 4 occurrences: function, method, line, function
    [ "$new_method" -eq 4 ]
    
    # Old method should count 3 lines
    [ "$old_method" -eq 3 ]
}

@test "comprehensive_validation.sh uses fixed counting method" {
    # Verify the comprehensive validation script uses the fixed method
    grep -q "grep -o.*| wc -l" "./comprehensive_validation.sh"
    
    # Verify the specific line uses the new method
    grep -q "grep -o \"行\|line\|関数\|function\|メソッド\" | wc -l" "./comprehensive_validation.sh"
}

@test "run_hook_validation.sh uses fixed counting method" {
    # Verify the run hook validation script uses the fixed method
    grep -q "grep -o.*| wc -l" "./run_hook_validation.sh"
    
    # Check that all grep -c patterns were replaced with grep -o | wc -l
    file_mentions=$(grep -c "grep -c" "./run_hook_validation.sh" || true)
    
    # Should be 0 occurrences of grep -c for pattern matching
    [ "$file_mentions" -eq 0 ]
}

@test "quality assessment handles edge cases correctly" {
    # Test empty text
    empty_result=$(echo "" | grep -o "行\|line\|関数\|function\|メソッド" | wc -l)
    [ "$empty_result" -eq 0 ]
    
    # Test no matches
    no_match_result=$(echo "This has no specific references" | grep -o "行\|line\|関数\|function\|メソッド" | wc -l)
    [ "$no_match_result" -eq 0 ]
    
    # Test multiple matches on same line
    same_line_result=$(echo "The function and method on line 42" | grep -o "行\|line\|関数\|function\|メソッド" | wc -l)
    [ "$same_line_result" -eq 2 ]
}

@test "quality assessment fix maintains scoring logic" {
    # Test a review with multiple specific references
    local review_with_refs="The function validateInput needs fixing. Also check method processData in line 42."
    
    # Count specific references manually
    local ref_count=$(echo "$review_with_refs" | grep -o "行\|line\|関数\|function\|メソッド" | wc -l)
    
    # Should count 2 references: function, line
    [ "$ref_count" -eq 2 ]
}
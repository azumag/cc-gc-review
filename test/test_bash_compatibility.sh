#!/bin/bash

# Test script to verify Bash compatibility across versions

set -euo pipefail

echo "=== Bash Compatibility Test ==="
echo "Testing with current Bash: $BASH_VERSION"

# Test associative array support
test_associative_arrays() {
    local bash_path="$1"
    local description="$2"

    echo "Testing $description ($bash_path)..."

    # Test associative array declaration
    result=$($bash_path -c 'declare -A test_array 2>/dev/null && echo "SUPPORTED" || echo "NOT_SUPPORTED"')

    if [ "$result" = "SUPPORTED" ]; then
        echo "  ✓ Associative arrays: SUPPORTED"
    else
        echo "  ✗ Associative arrays: NOT_SUPPORTED"
    fi

    # Test BASH_VERSINFO
    version_info=$($bash_path -c 'echo "${BASH_VERSINFO[0]:-0}.${BASH_VERSINFO[1]:-0}.${BASH_VERSINFO[2]:-0}"')
    major_version=$($bash_path -c 'echo "${BASH_VERSINFO[0]:-0}"')

    echo "  Version info: $version_info"
    echo "  Major version: $major_version"

    if [ "$major_version" -ge 4 ]; then
        echo "  ✓ Version check: Modern Bash (4.0+)"
    else
        echo "  ✗ Version check: Legacy Bash (<4.0)"
    fi

    echo ""
}

# Test system Bash (typically 3.2.57 on macOS)
test_associative_arrays "/bin/bash" "System Bash"

# Test homebrew Bash if available
if command -v brew >/dev/null 2>&1; then
    BREW_BASH="$(brew --prefix)/bin/bash"
    if [ -x "$BREW_BASH" ]; then
        test_associative_arrays "$BREW_BASH" "Homebrew Bash"
    else
        echo "Homebrew Bash not available at: $BREW_BASH"
    fi
else
    echo "Homebrew not available"
fi

echo "=== Compatibility Test Complete ==="

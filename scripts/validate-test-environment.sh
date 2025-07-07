#!/bin/bash
# Environment validation for gemini-review-hook testing

set -euo pipefail

echo "=== Test Environment Validation ==="

# Check required commands
REQUIRED_COMMANDS=("bash" "jq" "git" "gemini" "timeout")
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ Missing required command: $cmd"
        exit 1
    else
        echo "✅ $cmd: $(command -v "$cmd")"
    fi
done

# Check bash version
BASH_VERSION_MAJOR=$(echo "$BASH_VERSION" | cut -d. -f1)
if [ "$BASH_VERSION_MAJOR" -lt 3 ]; then
    echo "❌ Bash version $BASH_VERSION too old (need 3.0+)"
    exit 1
else
    echo "✅ Bash version: $BASH_VERSION (running under $(bash --version | head -1))"
fi

# Check jq version
JQ_VERSION=$(jq --version | sed 's/jq-//')
echo "✅ jq version: $JQ_VERSION"

# Check git repository
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "❌ Not in a git repository"
    exit 1
else
    echo "✅ Git repository detected"
fi

# Check gemini authentication
if ! echo "test" | gemini -p "respond with OK" --model=gemini-2.5-flash >/dev/null 2>&1; then
    echo "❌ Gemini authentication failed"
    exit 1
else
    echo "✅ Gemini authentication successful"
fi

echo "✅ All environment checks passed"

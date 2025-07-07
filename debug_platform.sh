#!/bin/bash

set -euo pipefail

echo "=== Platform Detection Debug ==="

# Test stat command detection
echo "Testing stat command detection:"
if stat -f "%m %N" /dev/null >/dev/null 2>&1; then
    echo "✓ Detected BSD stat (macOS)"
    echo "Testing BSD stat with a file:"
    touch test_file.txt
    stat -f "%m %N" test_file.txt
    rm test_file.txt
else
    echo "✓ Detected GNU stat (Linux)"
    echo "Testing GNU stat with a file:"
    touch test_file.txt
    stat -c "%Y %n" test_file.txt
    rm test_file.txt
fi

echo ""
echo "Testing find with stat:"
mkdir test_dir
touch test_dir/test1.jsonl
touch test_dir/test2.jsonl

if stat -f "%m %N" /dev/null >/dev/null 2>&1; then
    echo "Using BSD stat format:"
    find test_dir -name "*.jsonl" -type f -exec stat -f "%m %N" {} \;
else
    echo "Using GNU stat format:"
    find test_dir -name "*.jsonl" -type f -exec stat -c "%Y %n" {} \;
fi

rm -rf test_dir

echo ""
echo "Testing mktemp:"
temp_file=$(mktemp 2>/dev/null) && echo "✓ mktemp succeeded: $temp_file" && rm -f "$temp_file" || echo "✗ mktemp failed"
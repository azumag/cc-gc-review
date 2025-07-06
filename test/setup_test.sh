#!/bin/bash

# setup_test.sh - テスト環境のセットアップスクリプト

set -euo pipefail

# 色付き出力
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}=== Test Environment Setup ===${NC}"

# Batsのインストール確認
if ! command -v bats >/dev/null 2>&1; then
    echo -e "${RED}Error: bats is not installed${NC}"
    echo "Please install bats test framework:"
    echo "  macOS: brew install bats-core"
    echo "  Ubuntu: sudo apt-get install bats"
    echo "  Or clone from: https://github.com/bats-core/bats-core"
    exit 1
fi

# 必要なツールの確認
REQUIRED_TOOLS=("tmux" "jq" "timeout")
MISSING_TOOLS=()

for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        MISSING_TOOLS+=("$tool")
    fi
done

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
    echo -e "${RED}Error: Missing required tools:${NC}"
    for tool in "${MISSING_TOOLS[@]}"; do
        echo "  - $tool"
    done
    echo ""
    echo "Please install missing tools:"
    echo "  macOS: brew install tmux jq coreutils"
    echo "  Ubuntu: sudo apt-get install tmux jq coreutils"
    exit 1
fi

# テスト用ディレクトリの作成
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$TEST_DIR/test_helper"

# Batsヘルパーライブラリのセットアップ
echo -e "${YELLOW}Setting up bats helper libraries...${NC}"

# bats-supportをクローン/更新
if [ ! -d "$TEST_DIR/test_helper/bats-support" ]; then
    git clone https://github.com/bats-core/bats-support.git "$TEST_DIR/test_helper/bats-support"
else
    echo "bats-support already exists, skipping clone"
fi

# bats-assertをクローン/更新
if [ ! -d "$TEST_DIR/test_helper/bats-assert" ]; then
    git clone https://github.com/bats-core/bats-assert.git "$TEST_DIR/test_helper/bats-assert"
else
    echo "bats-assert already exists, skipping clone"
fi

echo -e "${GREEN}✓ All required tools are installed${NC}"
echo -e "${GREEN}✓ Test directory prepared${NC}"
echo -e "${GREEN}✓ Bats helper libraries installed${NC}"

# Batsのバージョン確認
echo "Bats version: $(bats --version)"
echo "Test directory: $TEST_DIR"

echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""
echo "To run tests:"
echo "  cd $TEST_DIR"
echo "  bats test_gemini_review_hook.bats"
echo "  or: ./run_tests.sh"
echo "  or: ./run_tests.sh -f test_gemini_review_hook.bats"
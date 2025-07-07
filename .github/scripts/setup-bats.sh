#!/bin/bash

# setup-bats.sh - Standardized BATS helper library setup for CI
# This script ensures consistent BATS environment across all workflows

set -euo pipefail

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}=== Setting up BATS Helper Libraries ===${NC}"

# Install bats-core if not already installed
if ! command -v bats >/dev/null 2>&1; then
    echo "Installing bats-core..."
    git clone https://github.com/bats-core/bats-core.git /tmp/bats-core
    cd /tmp/bats-core

    # Use modern Bash on macOS if available
    if [[ "$OSTYPE" == "darwin"* ]] && command -v brew >/dev/null 2>&1; then
        BASH_PATH=$(brew --prefix 2>/dev/null)/bin/bash
        if [ -x "$BASH_PATH" ]; then
            echo "Using modern Bash for installation: $BASH_PATH"
            sudo "$BASH_PATH" ./install.sh /usr/local
        else
            sudo ./install.sh /usr/local
        fi
    else
        sudo ./install.sh /usr/local
    fi

    cd -
    # Cleanup temporary directory safely
    if [ -d "/tmp/bats-core" ]; then
        rm -rf /tmp/bats-core
    fi
fi

# Verify bats installation
echo "Bats version: $(bats --version)"

# Create test helper directory
mkdir -p test/test_helper

# Install bats-support
if [ ! -d "test/test_helper/bats-support" ]; then
    echo "Installing bats-support..."
    git clone --depth 1 https://github.com/bats-core/bats-support.git test/test_helper/bats-support
else
    echo "bats-support already exists"
fi

# Install bats-assert
if [ ! -d "test/test_helper/bats-assert" ]; then
    echo "Installing bats-assert..."
    git clone --depth 1 https://github.com/bats-core/bats-assert.git test/test_helper/bats-assert
else
    echo "bats-assert already exists"
fi

# Install bats-file
if [ ! -d "test/test_helper/bats-file" ]; then
    echo "Installing bats-file..."
    git clone --depth 1 https://github.com/bats-core/bats-file.git test/test_helper/bats-file
else
    echo "bats-file already exists"
fi

# Verify all libraries are installed
echo -e "${YELLOW}Verifying BATS helper libraries...${NC}"
for lib in bats-support bats-assert bats-file; do
    if [ -d "test/test_helper/$lib" ]; then
        echo -e "${GREEN}✓ $lib installed${NC}"
    else
        echo -e "${RED}✗ $lib missing${NC}"
        exit 1
    fi
done

# Set BATS_LIB_PATH (libraries now exist)
BATS_LIB_PATH="$(pwd)/test/test_helper/bats-support:$(pwd)/test/test_helper/bats-assert:$(pwd)/test/test_helper/bats-file"
export BATS_LIB_PATH

echo -e "${GREEN}✓ BATS setup complete${NC}"
echo "BATS_LIB_PATH=$BATS_LIB_PATH"

# Write to GitHub environment if available
if [ -n "${GITHUB_ENV:-}" ]; then
    echo "BATS_LIB_PATH=$BATS_LIB_PATH" >>"$GITHUB_ENV"
    echo "✓ BATS_LIB_PATH added to GitHub environment"
fi

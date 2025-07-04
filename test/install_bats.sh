#!/bin/bash

# install_bats.sh - Bats testing framework installation script

set -euo pipefail

# 色付き出力
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}=== Bats Testing Framework Installation ===${NC}"

# OS detection
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

# Install bats on Linux
install_bats_linux() {
    echo -e "${YELLOW}Installing bats on Linux...${NC}"
    
    if command -v apt-get >/dev/null 2>&1; then
        # Ubuntu/Debian
        sudo apt-get update
        sudo apt-get install -y bats
    elif command -v dnf >/dev/null 2>&1; then
        # Fedora
        sudo dnf install -y bats
    elif command -v yum >/dev/null 2>&1; then
        # CentOS/RHEL
        sudo yum install -y bats
    else
        echo -e "${YELLOW}Package manager not found, installing from source...${NC}"
        install_bats_from_source
    fi
}

# Install bats on macOS
install_bats_macos() {
    echo -e "${YELLOW}Installing bats on macOS...${NC}"
    
    if command -v brew >/dev/null 2>&1; then
        brew install bats-core
    else
        echo -e "${YELLOW}Homebrew not found, installing from source...${NC}"
        install_bats_from_source
    fi
}

# Install bats from source
install_bats_from_source() {
    echo -e "${YELLOW}Installing bats from source...${NC}"
    
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Clone bats-core
    git clone https://github.com/bats-core/bats-core.git
    cd bats-core
    
    # Install
    if [[ "$EUID" -eq 0 ]]; then
        ./install.sh /usr/local
    else
        sudo ./install.sh /usr/local
    fi
    
    # Cleanup
    cd /
    rm -rf "$temp_dir"
}

# Install bats helper libraries
install_bats_helpers() {
    echo -e "${YELLOW}Installing bats helper libraries...${NC}"
    
    local test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local helper_dir="$test_dir/test_helper"
    
    mkdir -p "$helper_dir"
    
    # Install bats-support
    if [ ! -d "$helper_dir/bats-support" ]; then
        git clone https://github.com/bats-core/bats-support.git "$helper_dir/bats-support"
    fi
    
    # Install bats-assert
    if [ ! -d "$helper_dir/bats-assert" ]; then
        git clone https://github.com/bats-core/bats-assert.git "$helper_dir/bats-assert"
    fi
    
    # Install bats-file
    if [ ! -d "$helper_dir/bats-file" ]; then
        git clone https://github.com/bats-core/bats-file.git "$helper_dir/bats-file"
    fi
    
    echo -e "${GREEN}✓ Bats helper libraries installed${NC}"
}

# Install additional dependencies
install_dependencies() {
    echo -e "${YELLOW}Installing additional dependencies...${NC}"
    
    local os=$(detect_os)
    
    case "$os" in
        "linux")
            if command -v apt-get >/dev/null 2>&1; then
                sudo apt-get install -y tmux jq coreutils
            elif command -v dnf >/dev/null 2>&1; then
                sudo dnf install -y tmux jq coreutils
            elif command -v yum >/dev/null 2>&1; then
                sudo yum install -y tmux jq coreutils
            fi
            ;;
        "macos")
            if command -v brew >/dev/null 2>&1; then
                brew install tmux jq coreutils
            fi
            ;;
        *)
            echo -e "${YELLOW}Unknown OS, please install tmux, jq, and coreutils manually${NC}"
            ;;
    esac
    
    echo -e "${GREEN}✓ Dependencies installed${NC}"
}

# Verify installation
verify_installation() {
    echo -e "${YELLOW}Verifying installation...${NC}"
    
    local all_ok=true
    
    # Check bats
    if command -v bats >/dev/null 2>&1; then
        echo -e "${GREEN}✓ bats: $(bats --version)${NC}"
    else
        echo -e "${RED}✗ bats not found${NC}"
        all_ok=false
    fi
    
    # Check dependencies
    for cmd in tmux jq timeout; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ $cmd: available${NC}"
        else
            echo -e "${RED}✗ $cmd: not found${NC}"
            all_ok=false
        fi
    done
    
    # Check helper libraries
    local test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local helper_dir="$test_dir/test_helper"
    
    for helper in bats-support bats-assert bats-file; do
        if [ -d "$helper_dir/$helper" ]; then
            echo -e "${GREEN}✓ $helper: installed${NC}"
        else
            echo -e "${RED}✗ $helper: not found${NC}"
            all_ok=false
        fi
    done
    
    if [ "$all_ok" = true ]; then
        echo -e "${GREEN}✓ All components installed successfully${NC}"
        return 0
    else
        echo -e "${RED}✗ Some components are missing${NC}"
        return 1
    fi
}

# Main installation function
main() {
    echo "Detecting OS..."
    local os=$(detect_os)
    echo "Detected OS: $os"
    
    # Check if bats is already installed
    if command -v bats >/dev/null 2>&1; then
        echo -e "${GREEN}Bats is already installed: $(bats --version)${NC}"
    else
        case "$os" in
            "linux")
                install_bats_linux
                ;;
            "macos")
                install_bats_macos
                ;;
            *)
                echo -e "${RED}Unsupported OS: $os${NC}"
                echo "Please install bats manually from: https://github.com/bats-core/bats-core"
                exit 1
                ;;
        esac
    fi
    
    # Install helper libraries
    install_bats_helpers
    
    # Install dependencies
    install_dependencies
    
    # Verify installation
    if verify_installation; then
        echo ""
        echo -e "${GREEN}=== Installation Complete ===${NC}"
        echo "You can now run tests with:"
        echo "  cd test"
        echo "  ./run_tests.sh"
        echo ""
        echo "Or run individual test files:"
        echo "  bats test_cc_gen_review.bats"
        echo "  bats test_hook_handler.bats"
    else
        echo ""
        echo -e "${RED}=== Installation Failed ===${NC}"
        echo "Please check the error messages above and install missing components manually."
        exit 1
    fi
}

# Run main function
main "$@"
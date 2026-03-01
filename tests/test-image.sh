#!/bin/bash
set -euo pipefail

# Smoke test for the Dev Container base image.
# Run inside a container built from the Dockerfile.

FAILED=0

check() {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "PASS: $description"
    else
        echo "FAIL: $description"
        FAILED=1
    fi
}

echo "=== Dev Container Base Image Smoke Tests ==="
echo

# --- Tool existence ---
echo "--- Tool existence ---"
check "node is installed"       node --version
check "npm is installed"        npm --version
check "git is installed"        git --version
check "zsh is installed"        zsh --version
check "gh (GitHub CLI)"         gh --version
check "jq is installed"         jq --version
check "delta is installed"      delta --version
check "fzf is installed"        fzf --version
check "iptables is installed"   iptables --version
check "ipset is installed"      ipset --version
check "dig is installed"        dig -v
check "aggregate is installed"  which aggregate
check "nano is installed"       nano --version
check "vim is installed"        vim --version
check "sudo is installed"       sudo --version

# --- Claude Code ---
echo
echo "--- Claude Code ---"
check "claude is installed"     claude --version

# --- Playwright ---
echo
echo "--- Playwright ---"
check "playwright is installed" npx playwright --version

# --- Firewall script ---
echo
echo "--- Firewall script ---"
check "init-firewall.sh exists"        test -f /usr/local/bin/init-firewall.sh
check "init-firewall.sh is executable" test -x /usr/local/bin/init-firewall.sh

# --- Environment ---
echo
echo "--- Environment ---"
check "DEVCONTAINER=true"       test "$DEVCONTAINER" = "true"
check "SHELL is zsh"            test "$SHELL" = "/bin/zsh"
check "node user (UID 1000)"    test "$(id -u)" = "1000"
check "/workspace exists"       test -d /workspace
check "/home/node/.claude exists" test -d /home/node/.claude

# --- Sudoers ---
echo
echo "--- Sudoers ---"
check "sudoers file exists" test -f /etc/sudoers.d/node-firewall

echo
if [ $FAILED -eq 0 ]; then
    echo "All tests passed!"
else
    echo "Some tests FAILED!"
    exit 1
fi

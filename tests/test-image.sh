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
echo "--- Core tools ---"
check "node is installed"       node --version
check "npm is installed"        npm --version
check "git is installed"        git --version
check "zsh is installed"        zsh --version
check "gh (GitHub CLI)"         gh --version
check "jq is installed"         jq --version
check "delta is installed"      delta --version
check "fzf is installed"        fzf --version
check "iptables is installed"   iptables --version
check "ipset is installed"      which ipset
check "dig is installed"        dig -v
check "aggregate is installed"  which aggregate
check "nano is installed"       nano --version
check "vim is installed"        vim --version
check "sudo is installed"       sudo --version

# --- AI / MCP tools ---
echo
echo "--- AI / MCP tools ---"
check "claude is installed"     claude --version
check "bun is installed"        bun --version
check "uv is installed"         uv --version
check "uvx is installed"        uvx --version
check "pip3 is installed"       pip3 --version

# --- claude-mem stack ---
echo
echo "--- claude-mem stack ---"
check "claude-mem is installed"           test -d /usr/local/share/npm-global/lib/node_modules/claude-mem
check "chromadb is installed"             python3 -c "import chromadb"
check "ONNX model is cached"             test -d /home/node/.cache/chroma/onnx_models/all-MiniLM-L6-v2
check "claude-mem plugin symlink exists"  test -L /home/node/.claude/plugins/marketplaces/thedotmack/plugin
check "claude-mem scripts dir exists"     test -d /usr/local/share/npm-global/lib/node_modules/claude-mem/plugin/scripts

# --- Playwright ---
echo
echo "--- Playwright ---"
check "playwright is installed"   npx playwright --version
check "chromium browser exists"   test -d /home/node/.cache/ms-playwright/chromium-*
# Chrome is only installed on amd64 (not available for arm64)
if [ "$(dpkg --print-architecture)" = "amd64" ]; then
    check "chrome browser exists (amd64)" google-chrome --version
else
    echo "SKIP: chrome browser (not available on $(dpkg --print-architecture))"
fi

# --- Startup scripts ---
echo
echo "--- Startup scripts ---"
check "start-chromadb.sh exists"              test -f /usr/local/bin/start-chromadb.sh
check "start-chromadb.sh is executable"       test -x /usr/local/bin/start-chromadb.sh
check "start-claude-mem-worker.sh exists"     test -f /usr/local/bin/start-claude-mem-worker.sh
check "start-claude-mem-worker.sh is executable" test -x /usr/local/bin/start-claude-mem-worker.sh
check "init-claude-mem-settings.sh exists"    test -f /usr/local/bin/init-claude-mem-settings.sh
check "init-claude-mem-settings.sh is executable" test -x /usr/local/bin/init-claude-mem-settings.sh

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
check "/home/node/.claude exists"     test -d /home/node/.claude
check "/home/node/.claude-mem exists" test -d /home/node/.claude-mem
check "CLAUDE_MEM_SCRIPTS is set"     test -n "$CLAUDE_MEM_SCRIPTS"

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

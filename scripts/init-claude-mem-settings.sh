#!/bin/bash
# Initialize claude-mem settings and register plugin for Claude Code

# --- 1. claude-mem data settings (ChromaDB connection) ---
SETTINGS_FILE="$HOME/.claude-mem/settings.json"

if [ ! -f "$SETTINGS_FILE" ]; then
  echo "Creating claude-mem settings..."
  cat > "$SETTINGS_FILE" << 'EOF'
{
  "CLAUDE_MEM_CHROMA_MODE": "remote",
  "CLAUDE_MEM_CHROMA_HOST": "127.0.0.1",
  "CLAUDE_MEM_CHROMA_PORT": "8100",
  "CLAUDE_MEM_CHROMA_SSL": "false",
  "CLAUDE_MEM_PYTHON_VERSION": "3.11"
}
EOF
  echo "claude-mem settings created at $SETTINGS_FILE"
else
  echo "claude-mem settings already exist"
fi

# --- 2. Register thedotmack marketplace in Claude Code ---
# Without this registration, Claude Code won't discover claude-mem's hooks
# (PostToolUse, UserPromptSubmit, etc.), even though the MCP server works.
KNOWN_MKT="$HOME/.claude/plugins/known_marketplaces.json"
PLUGIN_DIR="$HOME/.claude/plugins/marketplaces/thedotmack"

# Ensure plugin symlink exists (volume mount may clear it)
mkdir -p "$PLUGIN_DIR"
if [ ! -L "$PLUGIN_DIR/plugin" ] && [ ! -d "$PLUGIN_DIR/plugin" ]; then
  ln -s /usr/local/share/npm-global/lib/node_modules/claude-mem/plugin "$PLUGIN_DIR/plugin"
  echo "Recreated claude-mem plugin symlink"
fi

# Add thedotmack to known_marketplaces.json if missing
if [ -f "$KNOWN_MKT" ]; then
  if ! python3 -c "import json,sys; d=json.load(open('$KNOWN_MKT')); sys.exit(0 if 'thedotmack' in d else 1)" 2>/dev/null; then
    python3 -c "
import json
with open('$KNOWN_MKT', 'r') as f:
    data = json.load(f)
data['thedotmack'] = {
    'source': {'source': 'local', 'path': '$PLUGIN_DIR'},
    'installLocation': '$PLUGIN_DIR',
    'lastUpdated': '$(date -u +%Y-%m-%dT%H:%M:%S.000Z)'
}
with open('$KNOWN_MKT', 'w') as f:
    json.dump(data, f, indent=2)
"
    echo "Registered thedotmack marketplace in Claude Code"
  else
    echo "thedotmack marketplace already registered"
  fi
else
  echo "known_marketplaces.json not found yet (will be created on first Claude Code launch)"
fi

# --- 3. Ensure npm dependencies are installed for hooks ---
PLUGIN_LINK="$PLUGIN_DIR/plugin"
if [ -d "$PLUGIN_LINK" ] && [ ! -d "$PLUGIN_LINK/node_modules" ]; then
  echo "Installing claude-mem plugin dependencies..."
  (cd "$PLUGIN_LINK" && npm install --omit=dev 2>/dev/null) || true
fi

# --- 4. Configure claude-mem native hooks in settings.json ---
# These hooks enable the observation pipeline (PostToolUse, SessionStart, etc.)
# Without them, claude-mem MCP server works but observations are never recorded.
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
WORKER_BASE="/usr/local/share/npm-global/lib/node_modules/claude-mem/plugin/scripts"
BUN_RUNNER="node ${WORKER_BASE}/bun-runner.js"
WORKER_CMD="${WORKER_BASE}/worker-service.cjs"

# Check if hooks are already configured
if [ -f "$CLAUDE_SETTINGS" ]; then
  HAS_HOOKS=$(python3 -c "
import json, sys
with open('$CLAUDE_SETTINGS') as f:
    d = json.load(f)
hooks = d.get('hooks', {})
# Check if SessionStart hooks reference claude-mem
for group in hooks.get('SessionStart', []):
    for h in group.get('hooks', []):
        if 'claude-mem' in h.get('command', '') or 'worker-service' in h.get('command', ''):
            sys.exit(0)
sys.exit(1)
" 2>/dev/null && echo "yes" || echo "no")
else
  HAS_HOOKS="no"
fi

if [ "$HAS_HOOKS" = "no" ]; then
  echo "Adding claude-mem hooks to settings.json..."
  python3 << 'PYEOF'
import json, os

settings_path = os.path.expanduser("~/.claude/settings.json")
worker_base = "/usr/local/share/npm-global/lib/node_modules/claude-mem/plugin/scripts"
bun_runner = f"node {worker_base}/bun-runner.js"
worker_cmd = f"{worker_base}/worker-service.cjs"

# Load existing settings or create new
if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
else:
    settings = {}

# Define claude-mem hooks
claude_mem_hooks = {
    "SessionStart": [
        {
            "matcher": "startup|clear|compact",
            "hooks": [
                {
                    "type": "command",
                    "command": f"{bun_runner} {worker_cmd} start",
                    "timeout": 60,
                },
                {
                    "type": "command",
                    "command": f"{bun_runner} {worker_cmd} hook claude-code context",
                    "timeout": 60,
                },
            ],
        }
    ],
    "UserPromptSubmit": [
        {
            "hooks": [
                {
                    "type": "command",
                    "command": f"{bun_runner} {worker_cmd} hook claude-code session-init",
                    "timeout": 60,
                }
            ]
        }
    ],
    "PostToolUse": [
        {
            "hooks": [
                {
                    "type": "command",
                    "command": f"{bun_runner} {worker_cmd} hook claude-code observation",
                    "timeout": 120,
                }
            ]
        }
    ],
    "Stop": [
        {
            "hooks": [
                {
                    "type": "command",
                    "command": f"{bun_runner} {worker_cmd} hook claude-code summarize",
                    "timeout": 120,
                },
                {
                    "type": "command",
                    "command": f"{bun_runner} {worker_cmd} hook claude-code session-complete",
                    "timeout": 30,
                },
            ]
        }
    ],
}

# Merge hooks (preserve existing non-claude-mem hooks)
existing_hooks = settings.get("hooks", {})
for event, hook_list in claude_mem_hooks.items():
    if event not in existing_hooks:
        existing_hooks[event] = hook_list
    else:
        # Check if claude-mem hooks already exist for this event
        has_cm = any(
            "worker-service" in h.get("command", "")
            for group in existing_hooks[event]
            for h in group.get("hooks", [])
        )
        if not has_cm:
            existing_hooks[event].extend(hook_list)

settings["hooks"] = existing_hooks

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)

print("claude-mem hooks added to settings.json")
PYEOF
else
  echo "claude-mem hooks already configured in settings.json"
fi

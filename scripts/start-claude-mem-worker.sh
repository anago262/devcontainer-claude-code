#!/bin/bash
# Start claude-mem worker service (HTTP API on port 37777)
#
# IMPORTANT: Uses `worker-service.cjs start` which internally spawns a
# daemon via setsid + detached:true. Previous approach (nohup bun ... &)
# failed because SIGHUP was still delivered when the postStartCommand
# shell terminated, killing the worker before the first Claude session.

WORKER_SCRIPT="${CLAUDE_MEM_SCRIPTS}/worker-service.cjs"
WORKER_PORT=37777

if [ ! -f "$WORKER_SCRIPT" ]; then
  echo "Warning: claude-mem worker-service.cjs not found at $WORKER_SCRIPT"
  exit 1
fi

# Patch: pass --ssl false explicitly to chroma-mcp (newer versions default to SSL)
if grep -q 'return s&&l.push("--ssl")' "$WORKER_SCRIPT" 2>/dev/null; then
  sed -i 's/return s&&l.push("--ssl")/return s?l.push("--ssl"):l.push("--ssl","false")/' "$WORKER_SCRIPT"
  echo "Applied --ssl false patch to worker-service.cjs"
fi

READINESS_URL="http://127.0.0.1:${WORKER_PORT}/api/readiness"

# Check if worker is already running and fully initialized
if [ "$(curl -s -o /dev/null -w '%{http_code}' "$READINESS_URL" 2>/dev/null)" = "200" ]; then
  echo "claude-mem worker is already running and ready on port ${WORKER_PORT}"
  exit 0
fi

# If health responds but readiness doesn't, worker is still initializing — wait for it
if curl -s "http://127.0.0.1:${WORKER_PORT}/api/health" > /dev/null 2>&1; then
  echo "claude-mem worker is running but still initializing, waiting for readiness..."
  for i in $(seq 1 30); do
    if [ "$(curl -s -o /dev/null -w '%{http_code}' "$READINESS_URL" 2>/dev/null)" = "200" ]; then
      echo "claude-mem worker is now ready"
      exit 0
    fi
    sleep 1
  done
  echo "Warning: claude-mem worker readiness timed out (30s)"
  exit 1
fi

# Start worker using the proper daemon mechanism.
# `worker-service.cjs start` spawns a detached daemon via setsid,
# which survives postStartCommand shell termination (unlike nohup + bun).
# It also waits internally for health (5s) + readiness (30s) before returning.
echo "Starting claude-mem worker daemon on port ${WORKER_PORT}..."
bun "$WORKER_SCRIPT" start

# Verify readiness after start command returns
if [ "$(curl -s -o /dev/null -w '%{http_code}' "$READINESS_URL" 2>/dev/null)" = "200" ]; then
  echo "claude-mem worker started and ready"
  exit 0
fi

# Fallback: wait a bit more if start returned but readiness isn't confirmed yet
for i in $(seq 1 10); do
  if [ "$(curl -s -o /dev/null -w '%{http_code}' "$READINESS_URL" 2>/dev/null)" = "200" ]; then
    echo "claude-mem worker started and ready"
    exit 0
  fi
  sleep 1
done

echo "Warning: claude-mem worker may not have fully initialized"
exit 1

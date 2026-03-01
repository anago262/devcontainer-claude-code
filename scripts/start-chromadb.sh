#!/bin/bash
# Start ChromaDB as a background process for claude-mem

CHROMA_DATA_DIR="$HOME/.claude-mem/chromadb-data"
CHROMA_LOG="$HOME/.claude-mem/chromadb.log"
CHROMA_PORT=8100

mkdir -p "$CHROMA_DATA_DIR"

# Check if ChromaDB is already running
if curl -s "http://127.0.0.1:${CHROMA_PORT}/api/v1/heartbeat" > /dev/null 2>&1; then
  echo "ChromaDB is already running on port ${CHROMA_PORT}"
  exit 0
fi

echo "Starting ChromaDB on port ${CHROMA_PORT}..."
nohup chroma run --host 127.0.0.1 --port "$CHROMA_PORT" --path "$CHROMA_DATA_DIR" > "$CHROMA_LOG" 2>&1 &

# Wait for startup
for i in $(seq 1 15); do
  if curl -s "http://127.0.0.1:${CHROMA_PORT}/api/v1/heartbeat" > /dev/null 2>&1; then
    echo "ChromaDB started successfully"
    exit 0
  fi
  sleep 1
done

echo "Warning: ChromaDB may not have started. Check $CHROMA_LOG"
exit 1

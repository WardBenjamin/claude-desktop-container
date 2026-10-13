#!/bin/zsh
# Build (if needed) and start the Claude Desktop container. Attach with ./mac.sh
set -euo pipefail
cd "$(dirname "$0")"
docker compose up -d --build
docker compose ps
echo "listening on localhost:14500 -> run ./mac.sh to attach"

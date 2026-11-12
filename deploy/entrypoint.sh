#!/bin/sh
set -e
mkdir -p "${HOME}/.hexhand" "${WORKSPACE_ROOT}"

# Carry an older CatDesk config forward so the workspace slug survives the rename.
if [ -d "${HOME}/.catdesk" ] && [ ! -f "${HOME}/.hexhand/config.toml" ]; then
  cp -a "${HOME}/.catdesk/." "${HOME}/.hexhand/" 2>/dev/null || true
fi

# HEXhand binds 127.0.0.1 only; publish a LAN-facing port so Caddy can reach it.
socat TCP-LISTEN:3201,fork,reuseaddr TCP:127.0.0.1:${PORT} &

# The app is a TUI and waits for a keypress at its splash. tmux gives it a real
# terminal that we can drive from outside the container.
exec tmux new-session -s hexhand -x 220 -y 50 "hexhand"

#!/usr/bin/env bash
# Start the HEXhand connector for a folder (Linux / macOS).
#
#   ./hexhand-here.sh              # current folder
#   ./hexhand-here.sh ~/work/site  # that folder
#
# If no token is set, one is generated, printed once, and stored in
# ~/.hexhand/connector_token so the server side can be configured with it.

set -euo pipefail

FOLDER="${1:-$(pwd)}"
cd "$FOLDER"
WORKSPACE="$(pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TOKEN_FILE="${HOME}/.hexhand/connector_token"
mkdir -p "$(dirname "$TOKEN_FILE")"
if [ ! -s "$TOKEN_FILE" ]; then
  python3 -c "import secrets;print(secrets.token_urlsafe(24))" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
  echo "Generated a connector token in $TOKEN_FILE"
fi

export HEXHAND_CONNECTOR_TOKEN="$(cat "$TOKEN_FILE")"
export HEXHAND_WORKSPACE="$WORKSPACE"
export HEXHAND_CONNECTOR_PORT="${HEXHAND_CONNECTOR_PORT:-3210}"

echo "HEXhand connector starting in: $WORKSPACE"
echo "port: $HEXHAND_CONNECTOR_PORT   token file: $TOKEN_FILE"
exec python3 "$HERE/hexhand-connect.py"

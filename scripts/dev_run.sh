#!/usr/bin/env bash
# Launches the Debug app off-screen for unattended checks. Usage:
#   scripts/dev_run.sh [KEY=VALUE ...]     start (kills a previous instance)
#   scripts/dev_run.sh --shot out.png      capture the main window
#   scripts/dev_run.sh --cmd "text"        send a command line to the app
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$ROOT/build/dev"
mkdir -p "$STATE"
case "${1:-}" in
  --shot)
    rm -f "$2"
    echo "shot $2" >> "$STATE/commands"
    for _ in $(seq 1 40); do [[ -s "$2" ]] && exit 0; sleep 0.25; done
    echo "no screenshot produced" >&2; exit 1
    ;;
  --cmd)
    echo "$2" >> "$STATE/commands"
    ;;
  *)
    pkill -x Coreader 2>/dev/null || true
    sleep 0.5
    : > "$STATE/debug.log"; : > "$STATE/commands"
    APP=$(ls -d "$ROOT"/build/DerivedData/*/Build/Products/Debug/Coreader.app | head -1)
    args=(--env COREADER_OFFSCREEN=1 --env "COREADER_DEBUG_LOG=$STATE/debug.log" --env "COREADER_COMMANDS=$STATE/commands")
    for kv in "$@"; do args+=(--env "$kv"); done
    open -gn "$APP" "${args[@]}"
    ;;
esac

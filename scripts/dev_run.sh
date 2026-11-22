#!/usr/bin/env bash
# Runs the Debug app off-screen for unattended checks (see docs/driving-the-app.md).
#   scripts/dev_run.sh [KEY=VALUE ...]     start (replaces this state dir's previous instance)
#   scripts/dev_run.sh --shot out.png      capture the window (absolute path)
#   scripts/dev_run.sh --cmd "text"        send one command line to the app
#   scripts/dev_run.sh --stop              quit the instance
# COREADER_DEV_STATE picks the state directory (default build/dev), so several
# instances can run side by side.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE="${COREADER_DEV_STATE:-$ROOT/build/dev}"
mkdir -p "$STATE"
stop() {
  if [[ -f "$STATE/pid" ]]; then kill "$(cat "$STATE/pid")" 2>/dev/null || true; rm -f "$STATE/pid"; fi
}
case "${1:-}" in
  --shot)
    rm -f "$2"
    echo "shot $2" >> "$STATE/commands"
    for _ in $(seq 1 60); do [[ -s "$2" ]] && exit 0; sleep 0.25; done
    echo "no screenshot produced" >&2; exit 1
    ;;
  --cmd)
    echo "$2" >> "$STATE/commands"
    ;;
  --stop)
    stop
    ;;
  *)
    stop
    sleep 0.5
    : > "$STATE/debug.log"; : > "$STATE/commands"
    APP="${COREADER_APP:-$(ls -d "$ROOT"/build/DerivedData/*/Build/Products/Debug/Coreader.app | head -1)}"
    # Run the binary directly: it stays in the background and never takes focus.
    env COREADER_OFFSCREEN=1 "COREADER_DEBUG_LOG=$STATE/debug.log" "COREADER_COMMANDS=$STATE/commands" "$@" \
      nohup "$APP/Contents/MacOS/Coreader" >/dev/null 2>&1 &
    echo $! > "$STATE/pid"
    disown || true
    ;;
esac

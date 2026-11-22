#!/usr/bin/env bash
# Starts the Debug app off-screen against a scratch library next to the state directory.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE="${COREADER_DEV_STATE:-$ROOT/build/dev}"
exec "$ROOT/scripts/dev_run.sh" "COREADER_LIBRARY=$STATE/library" "COREADER_CACHES=$STATE/caches" "COREADER_WINDOW_SIZE=${SIZE:-1320x860}" "$@"

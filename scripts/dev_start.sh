#!/usr/bin/env bash
# Starts the Debug app off-screen against the scratch library in build/dev.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$ROOT/scripts/dev_run.sh" "COREADER_LIBRARY=$ROOT/build/dev/library" "COREADER_CACHES=$ROOT/build/dev/caches" "COREADER_WINDOW_SIZE=${SIZE:-1320x860}" "$@"

#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: build_dmg.sh --app-path /path/to/App.app --output /path/to/output.dmg [--volume-name Name]
USAGE
}

APP_PATH=""
OUTPUT_PATH=""
VOLUME_NAME="CoReader"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-path)
      APP_PATH="$2"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --volume-name)
      VOLUME_NAME="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$APP_PATH" || -z "$OUTPUT_PATH" ]]; then
  echo "Missing required arguments." >&2
  usage
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH" >&2
  exit 1
fi

OUTPUT_DIR="$(dirname "$OUTPUT_PATH")"
mkdir -p "$OUTPUT_DIR"

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coreader-dmg-root.XXXXXX")"
cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

/bin/cp -R "$APP_PATH" "$STAGING_DIR/"
/bin/ln -s /Applications "$STAGING_DIR/Applications"

if [[ -f "$OUTPUT_PATH" ]]; then
  /bin/rm -f "$OUTPUT_PATH"
fi

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$OUTPUT_PATH" \
  >/dev/null

printf '%s\n' "$OUTPUT_PATH"

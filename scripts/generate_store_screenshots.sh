#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RAW_DIR="${STORE_SCREENSHOT_RAW_DIR:-$ROOT_DIR/store_assets/raw_screenshots}"
OUT_DIR="$ROOT_DIR/store_assets/screenshots"
PLATFORM="${1:-ios}"

case "$PLATFORM" in
  ios|android|all) ;;
  --help|-h)
    echo "Usage: bash scripts/generate_store_screenshots.sh [ios|android|all]"
    echo "Defaults to ios. Requires real device or simulator captures in STORE_SCREENSHOT_RAW_DIR."
    exit 0
    ;;
  *)
    echo "Unknown platform: $PLATFORM. Choose ios, android, or all." >&2
    exit 1
    ;;
esac

if ! command -v magick >/dev/null 2>&1; then
  echo "ImageMagick 'magick' is required." >&2
  exit 1
fi

files=(
  01_home_voice.png
  02_voice_conversation.png
  03_memory.png
  04_care_alert.png
  05_privacy_support.png
)

# Validate every selected source before replacing any existing store asset.
platforms=()
[[ "$PLATFORM" == ios || "$PLATFORM" == all ]] && platforms+=(ios_6_7)
[[ "$PLATFORM" == android || "$PLATFORM" == all ]] && platforms+=(android_phone)
for platform in "${platforms[@]}"; do
  for file in "${files[@]}"; do
    if [[ ! -f "$RAW_DIR/$platform/$file" ]]; then
      echo "Missing real app capture: $RAW_DIR/$platform/$file" >&2
      exit 1
    fi
  done
done

prepare_set() {
  local platform="$1"
  local width="$2"
  local height="$3"
  local source_dir="$RAW_DIR/$platform"
  local output_dir="$OUT_DIR/$platform"

  mkdir -p "$output_dir"

  for file in "${files[@]}"; do
    local input="$source_dir/$file"
    local output="$output_dir/$file"

    if [[ ! -f "$input" ]]; then
      echo "Missing real app capture: $input" >&2
      exit 1
    fi

    # Keep the full device capture visible, remove metadata/alpha, and emit the
    # exact store canvas size. The source must be a real app-in-use screenshot.
    magick "$input" \
      -auto-orient \
      -background '#FFF8EA' \
      -alpha remove \
      -alpha off \
      -resize "${width}x${height}" \
      -gravity center \
      -extent "${width}x${height}" \
      -strip \
      PNG24:"$output"
  done
}

for platform in "${platforms[@]}"; do
  case "$platform" in
    ios_6_7) prepare_set ios_6_7 1290 2796 ;;
    android_phone) prepare_set android_phone 1080 1920 ;;
  esac
done

echo "Prepared real app store screenshots in $OUT_DIR"

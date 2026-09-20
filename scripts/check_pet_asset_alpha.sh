#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "Usage: bash scripts/check_pet_asset_alpha.sh pet.png [pet.png ...]" >&2
  exit 2
fi
command -v magick >/dev/null 2>&1 || {
  echo "ImageMagick is required for read-only PNG inspection." >&2
  exit 2
}

failed=0
for asset in "$@"; do
  if [[ "$asset" != *.png || ! -f "$asset" ]]; then
    echo "FAIL: expected an existing PNG: $asset" >&2
    failed=1
    continue
  fi
  info=$(magick identify -format '%w %h %[channels] %[opaque] %[fx:mean.a] %[fx:p{0,0}.a] %[fx:p{w-1,0}.a] %[fx:p{0,h-1}.a] %[fx:p{w-1,h-1}.a]' "$asset")
  # Channel descriptions contain spaces, so inspect fields from the right.
  if ! awk '
    { if ($1 != $2 || $1 < 512 || $(NF-5) != "False") exit 1;
      if ($(NF-4) <= 0.05 || $(NF-4) >= 0.95) exit 1;
      for (i=NF-3; i<=NF; i++) if ($i != 0) exit 1;
    }' <<< "$info"; then
    echo "FAIL: $asset must be square >=512px, contain visible art and transparency, and have clear corners." >&2
    failed=1
  else
    echo "PASS: $asset (alpha structure only; visual edge and identity review still required)"
  fi
done
exit "$failed"

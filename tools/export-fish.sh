#!/bin/zsh
# Exports the fish into the app: ARFace/Resources/fish.usdz. See docs/fish-export.md.
#
#   tools/export-fish.sh [/tmp/facefish_export.blend]
#
# Takes the copy written by tools/save-export-copy.py inside Blender (command-line Blender can't read
# the working file in Google Drive). Runs Blender headless and never writes back to the .blend. The
# export scripts live on the `web` branch (blender/export_*.py) and are read from git, so nothing
# needs checking out.
set -euo pipefail

BLEND=${1:-/tmp/facefish_export.blend}
BLENDER=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
REPO=$(cd "$(dirname "$0")/.." && pwd)
BRANCH=${FACEFISH_SCRIPTS_BRANCH:-web}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

[[ -f "$BLEND" ]] || { echo "No $BLEND: run tools/save-export-copy.py in Blender first." >&2; exit 1; }
[[ -x "$BLENDER" ]] || { echo "Blender not found at $BLENDER (set BLENDER=...)" >&2; exit 1; }

# The scripts write to <their folder>/../public/models, so give them a folder of their own.
mkdir -p "$WORK/blender" "$WORK/public/models"
for script in export_rest.py export_fish.py export_usd.py; do
    git -C "$REPO" show "$BRANCH:blender/$script" > "$WORK/blender/$script"
done

echo "Exporting $(basename "$BLEND")…"
FACEFISH_SOURCE="${FACEFISH_SOURCE:-$(basename "$BLEND")}" FACEFISH_NO_GLTF=1 "$BLENDER" -b "$BLEND" \
    -P "$WORK/blender/export_rest.py" -P "$WORK/blender/export_fish.py" -P "$WORK/blender/export_usd.py" \
    > "$WORK/export.log" 2>&1 || true
grep -E '^\[(export|usd)\]' "$WORK/export.log" | cut -c1-200 || true
if grep -q "Traceback" "$WORK/export.log" || [[ ! -f "$WORK/public/models/fish.usdz" ]]; then
    echo "Export failed; Blender's log:" >&2
    tail -40 "$WORK/export.log" >&2
    exit 1
fi

cp "$WORK/public/models/fish.usdz" "$REPO/ARFace/Resources/fish.usdz"
echo "Wrote ARFace/Resources/fish.usdz ($(du -h "$REPO/ARFace/Resources/fish.usdz" | cut -f1))"

# What the app looks for, so a renamed or missing part shows up here rather than on stage.
if command -v usdtree > /dev/null; then
    TREE=$(usdtree "$REPO/ARFace/Resources/fish.usdz" 2>/dev/null)
    for part in Head TailRig PecRig_L PecRig_R DorsalRig Eye_L Eye_R Eyelid_L Eyelid_R lashesClosed; do
        grep -q -- "--$part " <<< "$TREE" || echo "WARNING: no $part in the export" >&2
    done
    echo "Blend shapes: $(grep -c 'BlendShape' <<< "$TREE")"
fi

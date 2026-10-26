#!/bin/sh
# Week 1 Pair M: assumes Pair P baseline has been applied to week1.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
command -v alr >/dev/null 2>&1 || { echo 'Install Alire (alr)' >&2; exit 1; }
command -v ffmpeg >/dev/null 2>&1 || { echo 'Install ffmpeg' >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo 'Install python3' >&2; exit 1; }

# Step 0: exercises the shared library, CLI, real export, proxy, and flow.
sh "$ROOT/scripts/week1_pair_p.sh"
(
    cd "$ROOT/tests"
    alr -n build
    ./bin/jpeg_header_tests
)

# Reference JPEG and raw RGBA from the same first frame of the proxy.
# Temporary directory prevents binary reference files from polluting git.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
ffmpeg -hide_banner -loglevel error -y \
    -i "$ROOT/examples/take1.mp4.proxy.mov" -frames:v 1 -c:v copy "$TMP/frame.jpg"
ffmpeg -hide_banner -loglevel error -y \
    -i "$TMP/frame.jpg" -frames:v 1 -f rawvideo -pix_fmt rgba "$TMP/frame.rgba"
python3 "$ROOT/scripts/jpeg_reference.py" "$TMP/frame.jpg" "$TMP/frame.rgba"
"$ROOT/tests/bin/jpeg_header_tests" "$TMP/frame.jpg"

# Adi2 is a separately pinned GUI dependency. Requires a desktop for launch.
(
    cd "$ROOT/ui"
    alr -n build
)
echo 'PASS: Pair M week 1 checks complete'
echo 'To view the GUI on a desktop: cd ui && ./bin/framewise_ui'

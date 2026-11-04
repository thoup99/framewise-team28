#!/bin/sh
# Compare every video frame Framewise.ISOBMFF.Parse resolves with ffprobe.
#
#   tests/compare_samples.sh examples/take1.mp4.proxy.mov
#
# Build the tests first (cd tests && alr build). For each frame this
# checks the file offset, the size and the start time, and it checks that
# Sample_At (Video, 5 s) is the frame ffprobe shows at pts = 5 s. It also
# runs the real-file truncation test. Unlike compare_tables.sh it only
# uses ffprobe's -show_entries output, which is stable, so CI runs it.
set -eu

if [ $# -ne 1 ] || [ ! -f "$1" ]; then
  echo "usage: $0 FILE.mov" >&2
  exit 2
fi
FILE=$1
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
command -v ffprobe >/dev/null 2>&1 || { echo 'ERROR: ffprobe not found' >&2; exit 2; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Ours: "FRAME index offset size start" lines, start in Framewise ticks.
if ! "$HERE/bin/parse_tests" "$FILE" | tr -d '\r' > "$TMP/run"; then
  grep '^FAIL' "$TMP/run" >&2 || true
  echo 'ERROR: parse_tests failed on the file' >&2
  exit 1
fi
grep '^FRAME ' "$TMP/run" | cut -d' ' -f2- > "$TMP/ours"
OURS_AT5=$(sed -n 's/^AT5 //p' "$TMP/run")

# Theirs. nk=0 names each field, because ffprobe prints them in its own
# order (pts,size,pos), not the order asked for. The pts are in the
# stream's time base, e.g. 1/15360; Framewise ticks are 1/90000 s, and
# Parse rounds down, so this does too.
TB=$(ffprobe -v error -select_streams v:0 -show_entries stream=time_base \
       -of csv=p=0 "$FILE" | tr -d '\r' | head -1)
ffprobe -v error -select_streams v -show_entries packet=pos,size,pts \
    -of csv=p=0:nk=0 "$FILE" | tr -d '\r' | awk -F, -v tb="$TB" '
  BEGIN { split(tb, r, "/"); num = r[1]; den = r[2] }
  {
    for (i = 1; i <= NF; i++) {
      split($i, kv, "=")
      v[kv[1]] = kv[2]
    }
    start = int(v["pts"] * 90000 * num / den)
    print NR, v["pos"], v["size"], start
    # The frame shown at exactly 5 s: pts * num / den = 5.
    if (v["pts"] * num == 5 * den) at5 = NR
  }
  END { print (at5 == "" ? "none" : at5) > "/dev/stderr" }' \
  > "$TMP/theirs" 2> "$TMP/theirs_at5"
THEIRS_AT5=$(cat "$TMP/theirs_at5")

FAILED=0
FRAMES=$(wc -l < "$TMP/theirs" | tr -d ' ')
if [ "$FRAMES" -eq 0 ]; then
  echo 'FAIL ffprobe shows no video packets'
  FAILED=1
elif diff "$TMP/ours" "$TMP/theirs" > "$TMP/diff"; then
  echo "PASS all $FRAMES frames: offset, size and start match ffprobe"
else
  echo 'FAIL frames differ (< ours, > ffprobe; index offset size start):'
  head -20 "$TMP/diff"
  FAILED=1
fi

if [ "$THEIRS_AT5" = "none" ]; then
  echo 'FAIL ffprobe shows no frame at exactly pts = 5 s'
  FAILED=1
elif [ "$OURS_AT5" = "$THEIRS_AT5" ]; then
  echo "PASS Sample_At (Video, 5 s) = frame $OURS_AT5, as ffprobe shows"
else
  echo "FAIL Sample_At (Video, 5 s): ours=$OURS_AT5 ffprobe=$THEIRS_AT5"
  FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
echo "samples match ffprobe for $FILE"

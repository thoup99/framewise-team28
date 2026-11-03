#!/bin/sh
# Compare the MOV sample tables Framewise reads with what ffprobe reads.
#
#   tests/compare_tables.sh examples/take1.mp4.proxy.mov
#
# Build the tests first (cd tests && alr build). For each track this
# checks the stsd entry type, the stts and stsc entry counts, the stsz
# sample count and uniform size, the chunk count, the total sample bytes
# and the first chunk offset. It also runs the real-file cut tests.
# It uses ffprobe's trace log, whose wording can change between ffmpeg
# versions, so it is a local check and not part of CI.
set -eu

if [ $# -ne 1 ] || [ ! -f "$1" ]; then
  echo "usage: $0 FILE.mov" >&2
  exit 2
fi
FILE=$1
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
command -v ffprobe >/dev/null 2>&1 || { echo 'ERROR: ffprobe not found' >&2; exit 2; }

# Ours: the COUNTS lines, with Ada's leading space after "=" removed.
OURS=$("$HERE/bin/table_reader_tests" "$FILE" | tr -d '\r' | grep '^COUNTS' | sed 's/= /=/g') || {
  "$HERE/bin/table_reader_tests" "$FILE" | grep -E '^FAIL' >&2
  echo 'ERROR: table_reader_tests failed on the file' >&2
  exit 1
}

# Theirs, part 1: counts from the box-by-box trace. The first stype line
# of a track is mdia's hdlr (vide or soun); minf's own hdlr says "url ".
TRACE=$(ffprobe -v trace "$FILE" 2>&1 >/dev/null | tr -d '\r' | awk '
  / stype=vide$/ { k = "video" }
  / stype=soun$/ { k = "audio" }
  /\.stts\.entries = / { stts[k] = $NF }
  /\.stsc\.entries = / { stsc[k] = $NF }
  /sample_size = [0-9]+ sample_count = / {
    for (i = 1; i <= NF; i++) {
      if ($i == "sample_size") size[k] = $(i + 2)
      if ($i == "sample_count") count[k] = $(i + 2)
    }
  }
  /type:.(stco|co64). parent:.stbl./ {
    for (i = 1; i <= NF; i++) if ($i == "sz:") box = $(i + 1)
    chunks[k] = (box - 16) / (index($0, "co64") ? 8 : 4)
  }
  END {
    for (k in stts)
      print k, stts[k], stsc[k], count[k], size[k], chunks[k]
  }')

# Theirs, part 2: the codec tag, and the packets for bytes and offset.
tag_of() {
  ffprobe -v error -select_streams "$1" -show_entries stream=codec_tag_string \
    -of csv=p=0 "$FILE" | tr -d '\r' | head -1
}
# Named fields: ffprobe prints them in its own order, not the asked one.
packets_of() {
  ffprobe -v error -select_streams "$1" -show_entries packet=pos,size \
    -of compact=p=0 "$FILE" | tr -d '\r' | awk -F'|' '
      {
        for (i = 1; i <= NF; i++) {
          split($i, kv, "=")
          if (kv[1] == "pos" && NR == 1) first = kv[2]
          if (kv[1] == "size") bytes += kv[2]
        }
      }
      END { print first + 0, bytes + 0 }'
}

field() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p"; }

FAILED=0
CHECKED=0
for KIND in video audio; do
  LINE=$(printf '%s\n' "$OURS" | grep "^COUNTS $KIND " || true)
  WANT=$(printf '%s\n' "$TRACE" | grep "^$KIND " || true)
  if [ -z "$LINE" ] && [ -z "$WANT" ]; then
    continue
  fi
  if [ -z "$LINE" ] || [ -z "$WANT" ]; then
    echo "FAIL $KIND track: ours='$LINE' ffprobe='$WANT'"
    FAILED=1
    continue
  fi

  STREAM=$(printf '%s' "$KIND" | cut -c1)
  set -- $WANT
  W_STTS=$2 W_STSC=$3 W_SAMPLES=$4 W_UNIFORM=$5 W_CHUNKS=$6
  set -- $(packets_of "$STREAM")
  W_FIRST=$1 W_BYTES=$2
  W_TAG=$(tag_of "$STREAM")

  # A fixed-size stsz stores no list, so our bytes are count * size.
  UNIFORM=$(field "$LINE" uniform)
  if [ "$UNIFORM" -eq 0 ]; then
    BYTES=$(field "$LINE" sizesum)
  else
    BYTES=$(( $(field "$LINE" samples) * UNIFORM ))
  fi

  for PAIR in "entry $(field "$LINE" entry) $W_TAG" \
              "stts $(field "$LINE" stts) $W_STTS" \
              "stsc $(field "$LINE" stsc) $W_STSC" \
              "samples $(field "$LINE" samples) $W_SAMPLES" \
              "uniform $UNIFORM $W_UNIFORM" \
              "chunks $(field "$LINE" chunks) $W_CHUNKS" \
              "bytes $BYTES $W_BYTES" \
              "first_offset $(field "$LINE" first) $W_FIRST"; do
    set -- $PAIR
    CHECKED=$((CHECKED + 1))
    if [ "${2:-}" = "${3:-}" ]; then
      echo "PASS $KIND $1 = $2"
    else
      echo "FAIL $KIND $1: ours=${2:-?} ffprobe=${3:-?}"
      FAILED=1
    fi
  done
done

if [ "$CHECKED" -eq 0 ]; then
  echo 'FAIL no video or audio track found to compare'
  FAILED=1
fi
if [ "$FAILED" -ne 0 ]; then
  exit 1
fi
echo "tables match ffprobe for $FILE"

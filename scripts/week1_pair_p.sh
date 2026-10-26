#!/bin/sh
# Step 0 verification for Pair P. Run from anywhere inside this repo.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

command -v alr >/dev/null 2>&1 || { echo 'ERROR: install Alire (alr)' >&2; exit 1; }
command -v ffmpeg >/dev/null 2>&1 || { echo 'ERROR: install ffmpeg' >&2; exit 1; }
command -v ffprobe >/dev/null 2>&1 || { echo 'ERROR: install ffprobe' >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo 'ERROR: install Python 3' >&2; exit 1; }

cd "$ROOT"
alr -n build
(
  cd tests
  alr -n build
  ./bin/tests
  ./bin/box_reader_tests
)
(
  cd cli
  alr -n build
  ./bin/framewise_cli ../examples/cut.fw </dev/null
)

cd "$ROOT/examples"
ffmpeg -loglevel error -y -f lavfi -i testsrc=size=1280x720:rate=30 -t 30 take1.mp4
ffmpeg -loglevel error -y -f lavfi -i smptebars=size=1280x720:rate=30 -t 20 take2.mp4
ffmpeg -loglevel error -y -f lavfi -i sine=frequency=440 -t 60 music.wav

../cli/bin/framewise_cli -c 'load cut.fw' -c 'export out.mp4'
DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 out.mp4)
if ! printf '%s\n' "$DURATION" | awk '{if ($1 > 21.9 && $1 < 22.1) exit 0; exit 1}'; then
  echo "ERROR: expected ~22 seconds; got $DURATION" >&2
  exit 1
fi

../cli/bin/framewise_cli -c 'load cut.fw' -c 'proxy take1'
test -s take1.mp4.proxy.mov
ffprobe -v error -show_streams take1.mp4.proxy.mov >/dev/null
ffprobe -v error -show_packets -select_streams v -read_intervals '%+#4' \
  take1.mp4.proxy.mov >/dev/null

# 'faststart' must put moov ahead of mdat for the future Decode.Open.
python3 - <<'PY'
import struct
from pathlib import Path
p = Path('take1.mp4.proxy.mov')
data = p.read_bytes()
i = 0
boxes = []
while i + 8 <= len(data):
    size, kind = struct.unpack_from('>I4s', data, i)
    header = 8
    if size == 1:
        if i + 16 > len(data):
            raise SystemExit('Truncated extended MOV header')
        size = struct.unpack_from('>Q', data, i + 8)[0]
        header = 16
    elif size == 0:
        size = len(data) - i
    if size < header or i + size > len(data):
        raise SystemExit('Invalid top-level MOV box')
    boxes.append(kind)
    i += size
if b'moov' not in boxes or b'mdat' not in boxes:
    raise SystemExit('Missing moov or mdat')
if boxes.index(b'moov') > boxes.index(b'mdat'):
    raise SystemExit('Expected faststart moov before mdat')
print('PASS: proxy moov precedes mdat')
PY

cd "$ROOT"
# GNATprove is required for the Step 0 proof baseline. Do not mask failures.
alr -n exec -- gnatprove -P framewise.gpr --mode=flow

echo 'PASS: Week 1 Pair P smoke checks complete'

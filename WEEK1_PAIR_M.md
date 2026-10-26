# Pair M — Week 1 (October 20, 2026)

This implementation targets `fall_semester_impl_plan.md`, Week 1 for
Pair M: **Step 0**, **M1 command bar / window foundation (D)**, and
**M2 reference JPEG and header reader (C)**. It is intentionally not
claiming completion of the multi-week GUI and decoder milestones.

## D: GUI skeleton, window, command bar

- `ui/` is now an Alire crate pinned to Framewise via `path = ".."`,
  with Adi2 pinned to its upstream GitHub repository.
- `ui/src/framewise_ui.adb` creates a native Adi2/SDL3 window with a
  single-line command entry field, Enter key handler, Run button,
  engine response label and read-only scrollable command log.
- The log keeps **the last 10 command/response entries**. It is UI
  state, **not** another edit model. All commands, including `load`,
  use `Framewise.Session.Execute`; no editing code calls Timeline,
  Plan, Commands or Decode directly.
- To load the example from inside `ui/`, enter
  `load ../examples/cut.fw`, then `list` or `info c1`.
- Timeline drawing, drag operations, import dialog and proxy-based
  preview are later steps (weeks 2–6), not Week 1 deliverables.

### Build and run

Install Alire 2.x, GNAT, SDL3, SDL3_ttf, SDL3_image and Python 3.
Adi2 is under active development; the build pins commit
`a6886c9` (master as inspected October 26, 2026).

```sh
cd ui
alr -n build
./bin/framewise_ui
```

This is a desktop GUI; it requires a graphical display. The project's
existing library and tests are built independently from the UI.

## C: Reference frame, baseline JPEG header

- `Framewise.JPEG.Read_Header` no longer returns `Ok=False` for every
  input. It validates SOI, walks length-delimited markers with guards,
  handles FF padding, locates SOF0 and returns width/height/components.
- For the Week 1 proxy path, it requires **8-bit, three-component,
  YCbCr 4:2:0** with Y sampling 2x2 and Cb/Cr 1x1, and rejects
  progressive, other sampling, out-of-range dimensions, malformed
  lengths and truncated inputs.
- `JPEG_Header_Tests` checks valid 960x540 data, numerous truncated
  prefixes, malformed segment lengths, unsupported markers and
  non-one-based Ada arrays.
- `scripts/jpeg_reference.py` inspects an actual MJPEG proxy frame:
  markers, SOF0, sampling factors, DQT/DHT counts and RGBA byte size.
- `Decode` remains deliberately unimplemented. Quantization/Huffman
  decoding, bit reader, IDCT and the MCU loop are weeks 2–5.

### Run references and tests

The script reuses the Step 0 export/proxy tests provided by Pair P,
then creates **temporary** `frame.jpg` and `frame.rgba` references
from the same proxy frame and runs Ada header tests.

```sh
sh scripts/week1_pair_m.sh
```

Or only the new generated-file-free Ada tests:

```sh
cd tests
alr -n build
./bin/jpeg_header_tests
```

## Scope and verification

- Pair P's box reader, timeline tests, proxy `faststart` flag and
  existing CI checks remain intact.
- Main CI includes JPEG header tests and reference-frame extraction,
  but GUI compilation is a **manual prerequisite check** until the
  pinned Adi2 dependency and installed SDL3 toolchain can be verified
  in the target CI environment. CI keeps its existing seam grep.
- Native Ada/Adi2 compilation and GNATprove have **not** been run in
  this authoring container (Alire/GNAT are absent). Do not report
  a passing Ada build or verified proof until the commands above
  run successfully on a configured machine.
- FFmpeg reference inspection *was* run on a generated 960x540 MJPEG
  frame and passed including the expected RGBA byte length.

## Required discussion for the weekly meeting

D: the native GUI command input and response history are implemented.
Needs confirmation of Adi2 build on teammates' Windows/Linux systems.

C: a defensive SOF0 4:2:0 header reader and regression tests are ready.
Next step: implement DQT, DHT, and bounded entropy bit reading.

Pair P and Pair M agree that the GUI's only modeling path remains
`Framewise.Session.Execute` and the document stays a replayable `.fw`
command history.

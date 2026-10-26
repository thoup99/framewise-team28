# Pair P — Week 1 (October 20, 2026)

Scope: `fall_semester_impl_plan.md` **Step 0**, **P1 begins** (student A),
**P2 begins** (student B). This is the first week of multi-week proof and
container tasks; it does **not** claim that P1/P2 are finished.

## Code changes

- `Framewise.ISOBMFF.Boxes` — a pure-Ada, SPARK-mode box-header reader.
  It supports 32-bit box sizes, 64-bit largesize (`size = 1`) and
  to-end-of-file boxes (`size = 0`). It rejects truncated headers, sizes
  smaller than the 8/16-byte header, boxes beyond the declared file
  size and sizes that do not fit Framewise's `Natural` offsets.
  Its input may contain only the box header while the payload remains
  on disk; the caller must check payload availability separately.
- `Box_Reader_Tests` — unit tests for valid standard/extended/EOF boxes,
  truncated byte arrays, malformed size values and non-one-based buffers.
- `Framewise.Session.Proxy_Command` — `-movflags +faststart` places the
  `moov` box before `mdat` for the future decoder's header-only read.
- `Framewise.Timeline` — initial proof-oriented loop invariants on the
  `Add_Source` and `Add_Track` search loops. Contracts are preserved.
- `P1_Foundation_Tests` — regression checks for `Clear`, source/track
  addition and lookup, duplicate rejection without mutation, and empty
  durations. These are tests, **not** formal proofs.
- `.gitignore` — ignores generated proxy MOV files.
- `scripts/week1_pair_p.sh` — a reproducible Step 0 smoke run, including
  synthetic input generation, export duration, proxy generation, MOV
  top-level box order, and GNATprove flow baseline.

## Run

From the repository root, install Alire, GNAT and `gnatprove` and the
FFmpeg development libraries per README. To add GNATprove to the Alire
workspace if necessary:

```sh
alr with gnatprove
```

Then run the week-1 checks:

```sh
sh scripts/week1_pair_p.sh
```

Or only the new tests:

```sh
cd tests
alr build
./bin/p1_foundation_tests
./bin/box_reader_tests
```

Start P1's proof run (zero unproved checks is the **weeks 1–3** target):

```sh
alr exec -- gnatprove -P framewise.gpr --mode=all -u framewise-timeline.adb
```

If individual checks are not proved, rerun with:

```sh
alr exec -- gnatprove -P framewise.gpr --mode=all -u framewise-timeline.adb --level=2 --timeout=60
```

**Record the prover summary before reporting P1 complete.** The Week 1
invariants are preparation, not a verified proof of the whole timeline.

## Step 0 expected evidence

- All existing and new Ada test binaries print no FAIL.
- `examples/out.mp4` duration is approximately 22 seconds and plays.
- `examples/take1.mp4.proxy.mov` exists; `ffprobe` recognizes it.
- The proxy has `moov` before `mdat`.
- `gnatprove --mode=flow` completes without errors.
- `Framewise.Session.Execute` handles modeling commands by applying
  them and recording successful ones in history; queries (`list`,
  `info`, `plan`) read state without adding history; `undo` removes the
  last modeling command then rebuilds state by replaying history.

## Not done in Week 1

- Formal proof of *all* timeline operations (`Delete`, `Place`, `Move`,
  `Trim`, `Split`): follows in weeks 2–3.
- MOV `moov/trak/stbl` traversal and table reading: week 2.
- Sample table resolution and `Sample_At`: week 3.
- `Decode.Probe`, `Decode.Open`, and optional import lengths: week 4.

## Local verification status

This generated change set was prepared without a GNAT/Alire toolchain
in the authoring environment. It must be compiled, tested and run
through GNATprove in CI or on a development machine before marking
Step 0 complete. No success is claimed without a run.

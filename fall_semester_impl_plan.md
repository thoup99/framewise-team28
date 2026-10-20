# framewise: fall semester plan (tentative/suggestion)

Four students, eight weeks, October 20 to December 11, 2026. This
document is the walkthrough. It tells you what to read, what to build,
in what order, how you know a step is done, and what usually goes
wrong. Read the README, then REQUIREMENTS.md, then ARCHITECTURE.md,
then this.

The seed already works end to end as an EDL editor: you can type
commands, save a `.fw` file, print the ffmpeg plan and export a real
mp4. What is missing is reading the proxy in pure Ada (`ISOBMFF`,
`JPEG`, `Decode`), the proof of the timeline, and the GUI. That is the
semester.

## What you will have on December 11

The acceptance demo in REQUIREMENTS.md Part 5 is for a full year. The
fall version, in a room, on a laptop:

1. Import three short clips and one song in the GUI. Watch the
   proxies get made.
2. Cut and arrange the clips in the GUI with the mouse. Watch the
   command bar print each line.
3. Scrub the playhead and see the frame at that moment, decoded by
   your JPEG decoder from your container parser.
4. Save. Open the `.fw` file in a text editor. Read it aloud.
5. Close the GUI. Replay the file in `framewise_cli`. Export. Play the
   mp4.
6. Feed a truncated proxy to the tool. It says `err`. It does not die.
7. Show `gnatprove --mode=all` clean on `Framewise.Timeline`, and the
   proof summary for `Framewise.ISOBMFF` and `Framewise.JPEG`.

Dropped from the fall, on purpose: ripple delete, beats and snapping,
overlay track, transitions, native export, real-time audio. Waveforms
are a stretch for the last week if the container parser lands early.

## The one rule: the library seam

This project scales only if you are disciplined about one boundary,
so it gets its own section before the schedule.

There are two executables, `cli/` and `ui/`. Both are **clients** of
the library in `src/`. A client does three things and nothing else:

1. It builds a text line and calls `Framewise.Session.Execute`.
2. It reads the response (`ok ...` or `err ...`) and shows it.
3. It redraws from `Sequence_Of (S)`, `Settings_Of (S)` and
   `History_Line (S, I)`, which are read-only copies.

The GUI gets one more door: `Framewise.Decode.Frame_At`, for the
preview. That is the full list.

"Easy to use from both the GUI and the CLI" sounds obvious and is
not. The failure mode is always the same: the GUI needs something, the
quickest way to get it is to reach into the library, and three weeks
later half the editor lives in `ui/` and the CLI cannot do what the
GUI does. Here is how you keep it from happening.

### The leak test

Any time you are about to write code in `ui/` or `cli/`, ask: **could
`framewise_cli` do this exact thing by typing a line?** If the answer
is no, you are not allowed to write it in the client. You go to the
library and add one of two things:

- a new **command** in `Framewise.Commands` (a `Parse` case, an `Image`
  case, a round-trip test, a line in the grammar comment, a `Session`
  dispatch). This is the default. Now the CLI, a script and an agent
  get the feature for free.
- a new **read-back function** on `Framewise.Session`, only when the
  thing is a question with a structured answer the GUI must draw
  (like `Sequence_Of`). It must return a copy or a value, never a
  reference into the session.

Then the GUI uses it like any other client.

### Smells that mean the seam is leaking

Each of these has happened in a previous capstone. If you see one in
a diff, stop and bring it to the meeting.

- `ui/` or `cli/` withs `Framewise.Timeline`, `Framewise.Plan` or
  `Framewise.Commands`. CI greps for it and fails. Do not "fix" the
  grep.
- The GUI keeps its own list of clips, tracks or sources, updated in
  parallel with the session. There is one model. The GUI reads it
  with `Sequence_Of` after every `Execute` and redraws. If that feels
  slow, measure it first; a `Sequence` is a bounded record, the copy
  is a memcpy.
- The GUI decides whether a drop is legal (overlap, past the end)
  before sending the line. It must not. It sends `move c3 13.5`, the
  kernel refuses or accepts, the bar shows the answer, the GUI redraws.
  Snapping and visual feedback while dragging are fine; the decision
  is not yours.
- The GUI modifies the `Sequence` it got from `Sequence_Of`, then
  draws it. The copy is for drawing. Every change goes through a line.
- A button does something that is not one line. Two lines are fine
  if each one is shown in the bar and each one goes through
  `Execute`. A button that does something no line can express is a
  new command waiting to be written.
- `Framewise.Session` grows a procedure that only makes sense for the
  GUI, like `Set_Zoom` or `Select_Clip`. Selection, zoom, playhead,
  scroll, colours, hover are **UI state**. They live in `ui/`, they
  are not in the document, they are not in the session.
- The CLI gets a flag or a special case that is not in the grammar
  (`--fps 60` on the command line instead of `settings 1280 720 60`
  as a line). The CLI is lines in, lines out, nothing else.
- `Framewise.Decode` starts doing things for the GUI that are not
  "give me the frame at T" (caching per widget, scaling to a window
  size it was told about last time, holding adi2 types). Decode knows
  bytes, times and RGBA buffers. Nothing else.

### The seam test you run every week

From `ui/README.md`, and it is the real detector: do a session in the
GUI, save it. Do the same session in `framewise_cli` by typing, save
it. Diff the two `.fw` files. They must be identical. If the GUI can
produce a document the CLI cannot, or the other way around, something
leaked. Run this before every weekly meeting from week 5 on.

## Team

Two pairs. Each pair owns one track for the semester and reviews the
other pair's diffs at the weekly meeting.

**Pair P (proof and container): students A and B.**
A owns the proof of `Framewise.Timeline`, then helps B prove
`Framewise.ISOBMFF`. B owns `Framewise.ISOBMFF`, `Framewise.Decode.Probe`
and `Framewise.Decode.Open`.

**Pair M (media and GUI): students C and D.**
C owns `Framewise.JPEG` and `Framewise.Decode.Frame_At`. D owns `ui/`
from day one, against the seed as it is, with no preview, and plugs
the preview in when C delivers.

Why D starts the GUI in week 1 with nothing to decode: it forces the
GUI to be built on the seam alone. If the GUI works against the seed
with only `Execute` and `Sequence_Of`, it will keep working when the
decoder arrives, and it cannot have leaked, because there was nothing
to leak into. A GUI started in week 5, after the decoder, always ends
up wrapped around the decoder.

All four: every feature lands with its test or its proof in the same
commit. CI stays green on the fork. Do not weaken a contract to make
something pass; fix the contract on its own with the reasoning in the
commit message.

## Step 0: everyone, week 1 (October 20)

Goal: fork built, tests green, a real export produced, every spec read.

Fork the seed. Clone your fork. Build the three crates.

```
alr build
```

```
cd tests && alr build && ./bin/tests
```

```
cd cli && alr build && ./bin/framewise_cli ../examples/cut.fw
```

Make the synthetic sources CI uses, in `examples/`:

```
ffmpeg -loglevel error -y -f lavfi -i testsrc=size=1280x720:rate=30 -t 30 take1.mp4
```

```
ffmpeg -loglevel error -y -f lavfi -i smptebars=size=1280x720:rate=30 -t 20 take2.mp4
```

```
ffmpeg -loglevel error -y -f lavfi -i sine=frequency=440 -t 60 music.wav
```

Then export and play the result:

```
../cli/bin/framewise_cli -c "load cut.fw" -c "export out.mp4"
```

Make a proxy and look at it, because the two placeholders you are
about to write read exactly this file:

```
../cli/bin/framewise_cli -c "load cut.fw" -c "proxy take1"
```

```
ffprobe -show_streams take1.mp4.proxy.mov
```

```
ffprobe -show_packets -select_streams v take1.mp4.proxy.mov | head -40
```

Run flow analysis so you know what clean looks like:

```
alr with gnatprove
```

```
alr exec -- gnatprove -P framewise.gpr --mode=flow
```

Done when: tests print no FAIL, `out.mp4` is 22 seconds and plays,
`take1.mp4.proxy.mov` exists, flow is clean, and each of you can
explain, without notes, what `Execute` does with a modeling command
versus a query versus `undo`.

Pair P reads `framewise-timeline.ads` top to bottom and the body of
`Place` and `Split`. Pair M reads `framewise-isobmff.ads`,
`framewise-jpeg.ads`, `framewise-decode.ads` and `ui/README.md`.

## Pair P, weeks 1 to 8

### Step P1: prove the timeline (A, weeks 1 to 3)

Goal: `gnatprove --mode=all` clean on `Framewise.Timeline`. S4, S5.

What is already there: every operation has `Well_Formed` as pre and
post. Flow is clean. What is missing: loop invariants in the body,
and probably a few lemma-shaped helpers so the prover can see that
`Insert_Sorted` and `Remove_At` keep the track sorted and
non-overlapping.

Work in this order, one operation at a time, and get each green
before the next:

1. `Clear`, `Add_Source`, `Add_Track`. These do not touch clips;
   their proof is mostly "the tracks I did not touch are unchanged".
2. `Find_*`, `Track_End`, `Sequence_End`. Pure reads.
3. `Delete`, which is a check plus `Remove_At`. Write the loop
   invariant for `Remove_At`: clips before `I` are unchanged, clips
   from `I` on are the old clips shifted by one, and the sorted
   property holds on the prefix done so far.
4. `Place`, which is a check plus `Insert_Sorted`. Same shape of
   invariant, the other direction.
5. `Move` and `Trim`. Each is a remove followed by an insert, or a
   check in place. Reuse what you proved.
6. `Split`. T3 is the one to state as a postcondition in its own
   words: the two resulting windows partition the original, and the
   right clip starts where the left one ends.

Run the prover on one unit at a time, with the level raised only when
a check will not go through:

```
alr exec -- gnatprove -P framewise.gpr --mode=all -u framewise-timeline.adb
```

```
alr exec -- gnatprove -P framewise.gpr --mode=all -u framewise-timeline.adb --level=2 --timeout=60
```

Traps:

- Do not prove by weakening. If a check does not go through, the
  invariant is incomplete, not the contract wrong. The one exception
  is a contract that is actually false; then fix it alone, in its own
  commit, and bring it to the meeting.
- The halving trick (`Start <= Time'Last / 2`, `Src_Out <= Time'Last / 2`)
  in `Clip_OK` exists so that `Ends` never overflows. If you see an
  overflow check on `Ends`, the prover has lost `Clip_OK` on that
  clip; add it to the invariant rather than reaching for a bigger
  type.
- `for all` over `1 .. T.Count - 1` with `Count = 0` is a null range,
  fine for Ada, sometimes confusing to read in a counterexample.
- Keep `-gnata` on in the tests. Runtime-checked contracts catch the
  mistakes the prover has not reached yet.

Done when: `--mode=all` reports zero unproved checks on
`Framewise.Timeline` at a level and timeout you write down in the
README, and CI runs that exact command.

### Step P2: the container (B, weeks 1 to 4)

Goal: `Framewise.ISOBMFF.Parse` and `Sample_At` work on the proxy,
`Decode.Probe` and `Decode.Open` work, `import` no longer needs
LENGTH. S6, S7, half of S8.

First decide where `moov` is. ffmpeg writes it at the end of a `.mov`
unless told otherwise, and the seed's `Proxy_Command` does not tell
it otherwise. You have two options. Pick the first.

Option 1, recommended: add `-movflags faststart` to `Proxy_Command`
in `Framewise.Session`. Then `moov` comes before `mdat`, and
`Decode.Open` reads the file from the start up to and including the
`mdat` box header, hands that to `Parse` as `Header`, and `Parse`
finds the `mdat` range from the last box header it sees. This keeps
the seed's `Parse` signature.

Option 2: keep the proxy command, have `Decode.Open` walk the
top-level boxes by seeking (8 bytes per box, skip by size), record the
`mdat` range itself, read only the `moov` bytes, and change `Parse`
to take `(Moov, Mdat_First, Mdat_Last, File_Size)`. More code in the
file layer, and a spec change to justify in the commit message.

Then build `Parse` in this order, each step with a test against
`ffprobe` output on `take1.mp4.proxy.mov`:

1. A box reader: given a byte array and an offset, return (type, size,
   payload first, payload last) or `Ok = False`. Handle `size = 1`
   (64-bit largesize) and `size = 0` (to end of file). Every later
   bound in the package comes from this one function being right, so
   test it on hand-built byte arrays, including truncated ones.
2. Walk `moov/trak/mdia/minf/stbl`. Identify the track by `hdlr`
   (`vide` or `soun`) and the codec by the `stsd` entry type (`jpeg`,
   and for audio `sowt`, `lpcm` or `twos`).
3. Read `stts`, `stsc`, `stsz`, `stco` or `co64` into bounded arrays.
   Reject a table that does not fit in `Max_Samples`.
4. Resolve: sample offset = chunk offset + sizes of the earlier samples
   in that chunk. Sample time = sum of earlier durations, in the
   `mdhd` timescale, then `T * Timebase / timescale`. Write the
   resolution as a loop you can state an invariant on: "samples 1 .. I
   are resolved and inside mdat".
5. `Inside` on every sample, or `Ok = False`.
6. `Sample_At`: binary search on `Samples (I).Start`.

Compare with ffprobe, which prints the offset (`pos`), size and
timestamp of every packet. Write a small script in `tests/` that
runs both and diffs the tables:

```
ffprobe -v error -select_streams v -show_entries packet=pos,size,pts -of csv=p=0 take1.mp4.proxy.mov
```

Then wire `Decode.Probe` (open, parse, report `Length` and which
tracks exist, close) and change `Session.Apply` so that `import NAME
FILE` with no LENGTH calls `Probe` on `FILE.proxy.mov` if it exists.
Keep LENGTH accepted; `examples/cut.fw` must still load.

Traps:

- All integers in the file are big-endian. Build one `Read_U32` and
  one `Read_U16` and use nothing else.
- `stsc` is run-length: an entry says "from chunk N on, M samples per
  chunk" until the next entry. The last run extends to the last chunk.
  This is the table everyone gets wrong once.
- `stts` is run-length too: (count, duration) pairs.
- The audio track in a proxy has thousands of tiny PCM samples per
  second grouped into chunks; it hits `Max_Samples` fast. Either
  treat one audio chunk as one sample for now (you only need chunk
  ranges to draw a waveform later) or raise the bound. Decide, write
  the reason in the spec comment.
- A truncated file must give `Ok = False` at every step. Make a test
  that cuts the proxy at ten random points and checks `Parse` never
  raises. That test is the demo's step 6.

Done when: `Probe` on the proxy reports the right length,
`Sample_At (Video, 5 s)` returns the sample ffprobe shows at
`pts = 5 s`, the truncation test passes, and `import take1 take1.mp4`
works after `proxy take1`.

### Step P3: prove the container (A and B, weeks 4 to 6)

Goal: `gnatprove --mode=all` on `Framewise.ISOBMFF` with the three
targets from the spec header: no index out of range, no overflow in
the offset arithmetic, `Well_Formed` as the postcondition of `Parse`.

Same method as P1, bottom up: box reader first (its postcondition is
that the returned range is inside the input), then each table reader,
then the resolution loop. The invariant you wrote in plain words in
P2 step 4 becomes the loop invariant.

Overflow is the real work here. Offsets are `Natural`; the file is at
most `File_Size` bytes; every sum must be shown to stay below it. A
guard like `if Offset > File_Size - Size then Ok := False` before each
addition is how you make that provable, and it is also how you make
it correct.

Done when: zero unproved checks at a documented level, and the
truncation test from P2 still passes (it is now the demonstration of
what the proof says).

### Step P4: waveform samples (B, weeks 7 to 8, stretch)

Only if P2 and P3 are green. Add `Decode.Samples_At (H, T, Count,
Buffer)` that returns PCM bytes around time T from the audio track.
PCM is just bytes, so this is one read. The GUI draws min/max per
pixel column from it. If this does not fit, skip it; the demo does
not need it.

## Pair M, weeks 1 to 8

### Step M1: the GUI skeleton, no preview (D, weeks 1 to 3)

Goal: an adi2 window that opens `examples/cut.fw`, draws two tracks
and four clips, has a command bar, and lets you drag a clip. U10,
U14, S10 against the seed as it is.

Set up `ui/` as the third crate, pinned to the library by path like
`cli/` is. Get an empty adi2 window up first and commit that.

Then build these, in this order, and commit each:

1. **The command bar.** A text field at the bottom. Enter sends the
   line to `Execute`, the response is shown next to it, the bar keeps
   the last ten lines. At this point the GUI is the CLI with a window.
   Load `examples/cut.fw` by typing `load ../examples/cut.fw`.
2. **The track view, read-only.** A custom-drawn widget. After every
   `Execute`, call `Sequence_Of (S)` and draw: one row per used track,
   one rectangle per clip at `x = Start * zoom`, width `Length * zoom`,
   with its name. Zoom and scroll are UI state in the widget. Nothing
   else is stored.
3. **Source list and Import button.** The list is drawn from
   `Sequence_Of (S).Sources`. Import opens a file dialog, then sends
   two lines: `import NAME FILE LENGTH` and `proxy NAME`. Until P2
   lands, LENGTH comes from a small dialog. Both lines show in the bar.
4. **Drag to move.** Mouse down on a clip, mouse move shows the ghost
   at the snapped position, mouse up builds `move NAME T` and sends
   it. On `err`, nothing moved, the bar says why, redraw. On `ok`,
   redraw. The GUI does not check for overlap. Ever.
5. **Drag an edge to trim**, builds `trim NAME IN OUT`. **Razor**
   (click at a time with the razor tool) builds `split NAME T NAME2`,
   where NAME2 is NAME with a suffix. **Delete key** builds
   `delete NAME`. **Ctrl-Z** builds `undo`.
6. **Playhead.** A vertical line you can drag. UI state. For now the
   preview area shows the name of the clip under the playhead and
   the time, computed from `Sequence_Of`. That rectangle is where the
   frame will go in M3.

Run the `ui/README.md` milestone 4 acceptance at the end of each
week: open `cut.fw`, drag `c3` left until it touches `c2`, read the
bar, drag it onto `c2`, read `err`, see nothing moved.

Traps:

- adi2 is a retained toolkit on SDL3. Read its examples before
  writing a custom widget; copy the structure of one of them.
- Build-time check first: `with Framewise.Session;` and
  `with Framewise;` are the only `with` lines for the library in
  `ui/`, until M3 adds `with Framewise.Decode;`. CI greps for anything
  else.
- `Sequence_Of` returns a `Timeline.Sequence`. You may read its
  fields. You may not `with Framewise.Timeline` to call operations on
  it. Reading the record type through `Session` is the intent.
- The temptation to keep a `Selected_Clip : Clip` copy is fine as UI
  state as long as it is a name, looked up again in `Sequence_Of`
  after every `Execute`. Copying the record and trusting it after a
  `move` is how the GUI shows stale data.

Done when: the milestone 4 acceptance passes with the seed library,
and a session done in the GUI and the same session typed into
`framewise_cli` give identical `.fw` files.

### Step M2: the JPEG decoder (C, weeks 1 to 5)

Goal: `Framewise.JPEG.Read_Header` and `Decode` produce the right
pixels for a frame pulled out of the proxy. Rest of S8 later; first
make it correct.

Get a reference. Pull one frame out of the proxy as its exact bytes,
and the same frame as raw RGBA from ffmpeg:

```
ffmpeg -y -i take1.mp4.proxy.mov -vframes 1 -c:v copy frame.jpg
```

```
ffmpeg -y -i frame.jpg -f rawvideo -pix_fmt rgba frame.rgba
```

Check the markers in `frame.jpg` before writing a line of code:

```
xxd frame.jpg | head -60
```

You should see `ffd8`, then `ffe0` or `ffe1`, `ffdb` (DQT), `ffc0`
(SOF0), `ffc4` (DHT, four of them), `ffda` (SOS). If `ffc4` is absent
the stream relies on the default tables from T.81 Annex K; ffmpeg's
MJPEG encoder writes them, but check, because a proxy made by another
tool may not.

Build in this order, each piece with its own test in `tests/`:

1. **Marker scanner and `Read_Header`.** Walk segments by length,
   stop at SOF0, read height, width, components and sampling factors.
   Check the proxy is 4:2:0 (Y 2x2, Cb 1x1, Cr 1x1). Reject anything
   else with `Ok = False`.
2. **DQT and DHT readers.** Quantization tables into 8x8 in zigzag
   order. Huffman tables as (code length counts, symbols); build the
   canonical code table from them. Test: the number of symbols equals
   the sum of the counts, every code is unique.
3. **The bit reader.** Reads bits from the scan data, handles `FF00`
   stuffing, stops at any other `FFxx` marker. Bounded on any input:
   past the end it returns zeros and sets a flag; it never indexes
   past the array. This is the heart of the "cannot crash" proof,
   so write it small and plain.
4. **One block.** DC symbol, extra bits, sign extension, DC predictor;
   AC run-length pairs, `0x00` end of block, `0xF0` sixteen zeros.
   Test on the first block of the frame against a value you compute
   by hand or with a tiny Python script using the same tables.
5. **Dequantize, un-zigzag, IDCT.** Use the plain separable
   row-column integer IDCT. It is slow and it is the one you can
   bound: 12-bit coefficient times 8-bit basis times 8 terms per
   pass, so every accumulator fits in 32 bits with room. Add 128,
   clamp to 0 .. 255.
6. **MCU loop.** 16x16 pixels: four Y blocks, one Cb, one Cr, left to
   right, top to bottom. Handle restart markers (reset DC predictors)
   even though ffmpeg does not write them.
7. **Colour.** Nearest-neighbour upsample of Cb and Cr, YCbCr to RGB
   in fixed point times 256, clamp, write RGBA with A = 255.

Compare with the reference, allowing a small per-channel tolerance
because the IDCT rounding differs from libjpeg's:

```
alr exec -- ./tests/bin/jpeg_compare frame.jpg frame.rgba
```

Where `jpeg_compare` is a test program you write that decodes with
your package, compares every pixel, and prints the maximum and mean
absolute difference. Aim for a maximum of 2 and a mean under 0.5.
Anything larger means a bug, not rounding; the usual ones are
un-zigzag order, the sign extension of the extra bits, and the DC
predictor not being per component.

Then the robustness test, which is the demo's step 6 for the codec:
truncate `frame.jpg` at twenty random points and at every marker
boundary, decode each, assert `Ok = False` or a correct partial
image, and no exception.

Traps:

- Width and height are not multiples of 16. The MCU grid is rounded
  up; the last column and row of MCUs are partly outside the image.
  Decode them fully, write only the pixels inside.
- The AC coefficient index after a run of zeros can exceed 63 on a
  corrupt stream. Bound it and bail with `Ok = False`.
- A Huffman code that matches nothing after 16 bits is a corrupt
  stream. Bail. Never loop looking for it.
- Do not try to be fast until the frame is right. 540p at the plain
  IDCT is a few tens of milliseconds, which is fine for a scrub bar.

Done when: the comparison passes on five frames from each of
`take1` and `take2`, the truncation test passes, and the whole thing
is SPARK with flow clean.

### Step M3: Frame_At and the preview (C and D, week 6)

Goal: `Decode.Frame_At` works, the GUI shows the frame under the
playhead. U11.

C writes `Frame_At`: `Sample_At`, one read of `Size` bytes at
`Offset`, `Read_Header`, `Decode` into a 540p buffer, nearest
neighbour scale to the requested width and height. Cache the last
decoded sample index so a scrub bar that asks for the same frame
twenty times decodes it once.

D plugs it in: an image widget in the preview rectangle, fed by
`Frame_At` at the playhead time, from the proxy of the clip under the
playhead. The time passed is `Clip.Src_In + (Playhead - Clip.Start)`,
computed from `Sequence_Of`. Step one frame forward or back with the
arrow keys, which is `1 / FPS` seconds of ticks, read from
`Settings_Of`.

Thumbnails: `Frame_At` at each clip's `Src_In`, scaled to the clip
rectangle height, cached in the GUI by (source name, time). That cache
is UI state.

Done when: dragging the playhead over `cut.fw` with proxies made
shows the test pattern frames changing, and stepping one frame moves
the pattern by one frame.

### Step M4: prove the decoder (C, weeks 7 to 8)

Goal: `gnatprove --mode=all` on `Framewise.JPEG` for the two targets
in the spec header: no index out of range in the Huffman lookup and
the bit reader on any input, no overflow in the IDCT accumulators.

The bit reader and the Huffman lookup first; they are small and the
truncation tests already show what the contract is. Then the IDCT
accumulators, which is a range proof: declare the coefficient and
accumulator subtypes with the bounds you worked out in M2 step 5 and
let the prover check the arithmetic.

Do not aim to prove the whole package in two weeks. Prove the two
targets, record the summary, and list what is left in the README.
That list is the spring's first task.

Done when: the two targets are proved at a documented level and the
summary is in the README.

## Week by week

| Week | Dates | Pair P | Pair M |
|---|---|---|---|
| 1 | Oct 20 | Step 0; A starts P1; B starts P2 box reader | Step 0; D starts M1 command bar; C starts M2 reference and header |
| 2 | Oct 27 | A: Delete, Place proved; B: tables read | D: track view, import; C: DQT, DHT, bit reader |
| 3 | Nov 3 | A: Move, Trim, Split proved; B: resolution and `Sample_At` | D: drag, trim, razor, undo; C: one block decoded |
| 4 | Nov 10 | A: P1 done, joins P3; B: Probe, Open, `import` without LENGTH | D: playhead, milestone 4 acceptance; C: IDCT, MCU loop |
| 5 | Nov 17 | P3: box reader and tables proved | D: seam test, polish; C: colour, comparison passes |
| 6 | Nov 24 | P3: resolution loop proved | M3: Frame_At, preview, thumbnails |
| 7 | Dec 1 | P4 waveform (stretch) or P3 finish | C: M4 proof; D: Import runs proxy, demo flow |
| 8 | Dec 8 | Demo rehearsal, README | Demo rehearsal, README |

Weeks 7 and 8 are deliberately light on new features. Everything in
the demo list at the top must be rehearsed twice before December 11,
once by each pair driving the other pair's work.

## Every week, before the meeting

- CI green on the fork, with the proof commands and levels written in
  the README.
- The seam test from week 5 on: GUI session and CLI session, diffed
  `.fw` files, identical.
- Come with the diff open, on the branch you will point to.
- One slide or one paragraph per pair: what is done, what is blocked,
  what you need decided.

## Rules of the road, repeated

- `src/` below `Framewise.Session` has no I/O and no allocation.
  `Framewise.Decode` is the one exception and it only reads.
- `Framewise.ISOBMFF` and `Framewise.JPEG` are pure functions over
  byte arrays. No file handles, no C.
- Every timeline operation: well-formed in, well-formed out, or
  `Ok = False` and the sequence untouched. Never an exception.
- Every new command gets a `Parse` case, an `Image` case, a
  round-trip test, and a line in the grammar comment.
- Nothing in `ui/` or `cli/` withs anything below `Framewise.Session`,
  except `Framewise.Decode` in `ui/` for the preview.
- If the GUI needs it and the CLI cannot type it, it is not allowed
  yet. Make it a command first.
# ui: the contract

The timeline supports clip movement, trimming, splitting, deletion and undo.
Drag the time ruler to scrub. The preview shows the active video clip and
timeline time, or “No video clip” in a gap. Scrubbing is local to the UI and
adds no edit to undo or save. The GUI follows three rules.

1. **Nothing in `ui/` withs anything below `Framewise.Session`.** The
   GUI sees `Framewise.Session` (Execute, Sequence_Of, Settings_Of,
   History_*) and `Framewise` (Time, Name, Path). It never sees
   `Framewise.Timeline` operations, `Framewise.Plan`, or
   `Framewise.Commands`. `Framewise.Decode` is the one exception, for
   the preview, once milestone 3 exists.
2. **Every gesture builds a line and calls `Execute`.** Drag a clip:
   `move c1 12.5`. Drag its edge: `trim c1 2 9`. Press the razor:
   `split c1 4 c1b`. The line is shown in a command bar at the bottom
   of the window before it runs, and the response after. A user who
   watches the bar for an hour can write `.fw` files.
3. **Rendering reads `Sequence_Of (S)` after every `Execute`** and
   draws the tracks from it. It never mutates a sequence. Selection,
   zoom, playhead, colours and snapping are UI state, not session
   state, and are not saved in the document.

## Suggested stack

- Window and input: [adi2](https://github.com/ovenpasta/adi2). The
  command bar is a text field; the source list is a list widget; the
  track view is a custom-drawn widget (rectangles with labels, one
  row per track, x = time * zoom).
- Preview: an image widget fed by `Framewise.Decode.Frame_At` at the
  playhead time, from the proxy (milestone 3). Until then, draw the
  clip name. An Import button runs `import` then `proxy`.
- Thumbnails: `Frame_At` at each clip's `Src_In`, cached by
  (source, time).

## Milestone 4 acceptance

Open `examples/cut.fw`, see two tracks and four clips, drag `c3` left
until it touches `c2`, read the bar: `move c3 13.5`. Drag it onto
`c2`: the bar shows the line and `err cannot move: unknown clip or
overlap`, and nothing moved. Press Export, get `out.mp4`. Then do the
same session in `framewise_cli` by typing, and diff the two saved
`.fw` files: identical.

For the export check, run the GUI and CLI from the directory containing
`take1.mp4`, `take2.mp4`, and `music.wav` so the relative paths in
`cut.fw` resolve. With the example loaded, scrub to 6.5 s (a video gap)
and 8.5 s (the start of c2). After the accepted and rejected moves above,
press **Export out.mp4**, then enter `save gui.fw`. In a fresh CLI session,
load the example, enter the same moves, then `save cli.fw`. Compare the
files with `diff gui.fw cli.fw` or `fc /b gui.fw cli.fw` on Windows.

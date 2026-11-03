# Week 2 GUI review

Scope: the week-by-week table in `fall_semester_impl_plan.md`, week 2,
student D: **track view, import**. Week 3 mouse editing has not started.

## Build and launch

With the same Alire and SDL3/SDL3_ttf/SDL3_image development setup used
for the existing GUI:

```sh
git switch week3-gui
git pull --ff-only
cd ui
alr build
alr run
```

Run from `ui/` so the example command below resolves correctly.

## Verify

1. Enter `load ../examples/cut.fw`. Expect `ok`, two rows (`v1`, `a1`),
   four blue clip rectangles (`c1`, `c2`, `c3`, `m1`), and three sources.
   Clip starts are 0, 8.5, 14, and 0 seconds; widths represent 6.5, 5, 8,
   and 22 seconds respectively. Gaps are visible.
2. Use **Zoom + / -** and **Earlier / Later 5s**. The ruler and rectangles
   move together, with track labels fixed. Clips outside the viewport are
   hidden/clipped. These controls do not add document/history commands.
   Additional tracks are accessible by vertical scrolling in the track area.
3. Enter `move c3 13.5`, then `move c3 10`. The first moves the drawing;
   the second reports overlap and leaves it in place. Enter `undo` to
   see the session redraw. These are typed commands, not week 3 gestures.
4. Click **Import file...**, cancel the file picker: no command or source
   should be added. Select a media file next time; a small dialog asks
   for source name, file path, duration in seconds, and kind (`video`,
   `audio`, or `both`). Cancel here also makes no edit.
5. Import with a new name and positive duration. Expect the exact
   `import NAME FILE LENGTH KIND` line and response in the last-ten-command
   log, plus a new source entry with kind, duration, and path. Import does
   not place a clip on a track. Invalid duration/kind or a duplicate name
   keeps the dialog open with the engine error and leaves the model intact.
6. Empty/whitespace-containing fields are rejected before submission.
   **The current shared parser does not support spaces in paths**; choose
   a path without spaces. This GUI does not invent quoting that the CLI
   cannot replay. Entering an import manually still follows the same parser.
7. Enter eleven commands such as `list`; only the latest ten command/reply
   pairs should remain. Imports participate in that same history.
8. Enter `save /tmp/week2.fw` (or a suitable Windows path without spaces).
   Zoom and scroll settings must not appear in the file.

Automatic `proxy NAME` after import is scheduled in week 7 in the weekly
table, despite appearing in the broader M1 description. It remains a typed
command for this week 2 checkpoint. Drag, trim, razor, delete-key, undo
shortcut, and playhead interactions remain for their scheduled weeks.

## Regression checks

```sh
cd ui
alr exec -- gprbuild -P ui_checks.gpr
./bin/timeline_view_tests
```

These checks exercise the actual custom widget's generated rectangles:
example positions and widths, two rows, accepted/rejected edits, clipping,
zoom, deletion/undo refresh, clearing the session, and no history edits
from changing the view. They do not substitute for the native file-picker
and interactive visual checks above.

## Validation completed for this checkpoint

- Built the Framewise library and the GUI executable with GNAT 16.1.
- Passed `tests`, `p1_foundation_tests`, `box_reader_tests`, and
  `jpeg_header_tests`.
- Passed `timeline_view_tests` against the pinned adi2 toolkit.
- Rendered and visually inspected the loaded example and import dialog
  using SDL's headless software renderer.
- Exercised the actual import callback for success, duplicate-name failure,
  and whitespace-path rejection; checked the command/reply history.
- Passed the UI dependency-boundary scan and `git diff --check`.

Native file-picker behavior and desktop interaction still need the user
review above. SPARK proofs and video export were not rerun for these UI-only
changes.

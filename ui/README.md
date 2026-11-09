# Framewise desktop editor

The editor uses a traditional layout inspired by OpenShot: a File menu at the top, Project Files on the left, Video Preview on the
right, and a full-width timeline below. Users edit through menus, buttons,
dialogs and timeline gestures. An optional Console button at the far right
of the top bar opens a floating command console.

Drag the blue vertical divider between Project Files and Video Preview to
change their widths. Drag the horizontal divider above the timeline controls
to change the upper workspace and timeline heights. Pane contents follow the
new dimensions; toolbar rows wrap and crowded panes scroll. Minimum sizes
keep both sides accessible. Proportions are retained while resizing the window
for the current session and do not modify the project document.

Mouse cursors follow the current action: left/right arrows on the vertical
pane divider, up/down arrows on the horizontal divider, a move cursor over
clip bodies, left/right arrows at trim edges and on the ruler, and the default pointer
on clips in razor mode. Buttons and dropdowns use a hand; editable fields use
a text cursor. Drag cursors remain active until release. Native cursors are
cached and released when the editor closes.

Project Files has **All**, **Video**, and **Audio** filters. All is selected
initially and when starting or opening a project. The active filter is lit
blue and also filters the Select media dropdown in the timeline. Combined video/audio
sources appear in both Video and Audio. Filtering changes only the view;
it does not remove sources or edit the project.

Each timeline track shows **Video**, **Audio**, or **Video + Audio** beneath
its name, including when the track is empty. The label reflects the track
type chosen when it was created.

When tracks exceed the timeline viewport, a vertical scrollbar appears on
its right edge. Drag the thumb, click the scrollbar track or use the wheel
to reach tracks below the viewport. It hides when all tracks fit.

Hold **Shift** while dragging a clip body to snap either edge to a neighboring
clip on the same track when it is within 10 screen pixels. Hold **Control** to
snap the clip's start to the interval set in **Snap (s)** immediately after
**Later**. The default is 0.5 seconds; positive decimal values such as 0.25 or 1
are supported. Empty or invalid input is marked red and keeps the last valid
interval active. Halfway values round forward. With both held, a nearby valid
clip edge takes priority, otherwise the configured interval applies. Modifier changes update the preview even without
moving the pointer. Release commits one move command; overlap validation still
applies. The dragged clip and its label are drawn above the other clips.
Trim handles keep their existing behavior.

## Optional console

Click **Console** in the upper-right corner to open **Framewise Console** above
the editor as a centered modal window. Editor controls are blocked until it
is closed; clicking the background does not dismiss it. The command field
receives focus immediately and has a bright blinking caret and a `>` prompt. Press **Enter** or **Run** to submit a command;
the scrollable transcript shows the command and its response, including errors.
**Close** or **Escape** returns to the editor. The transcript and unfinished
input remain available when the console is reopened during the same session.

The console uses the same project session as the GUI. For example,
`track Main_Video video` creates a track and refreshes the timeline and target
track selector; `list` inspects the current project and `undo` undoes its latest
edit. Command entries retain their origin labels: `[Editor]` for editor
operations and `[Console]` for typed commands. Typed commands appear once;
selection, filters, zooming, scrolling, and resizing are not logged.
Editor operations are recorded even while the console is closed, including
opening a project and deleting clips. Open the console after editing to inspect
the commands and their results. Closing it retains the transcript and unfinished
input for the current application session. Recording does not open the console
or change input focus or the caret position. Validation errors caught before a
command runs (such as an invalid track name, unsupported path, or missing
selection) are also recorded with the action name and an `err` response.
Canceled dialogs and view-only controls do not create command entries.

Successful `save path.fw` and `load path.fw` commands also update the
current document path, window title, and unsaved-change state. Console commands
use the existing Framewise syntax and validation; they are optional.

## Current workflow

1. Use **File > Open Project** to open an existing `.fw` document, or
   **New Project** to start empty.
2. Choose **Import Files** and select a media file. Enter its duration in
   seconds and choose `video`, `audio`, or `both`. Duration is still manual
   at this stage of the semester plan. Imported files appear in Project
   Files and the Select media dropdown in the timeline.
3. Use **Add Track** to enter a track name and choose video, audio or combined
   media. Names use up to 32 letters, numbers or underscores; a generated
   name is supplied as a starting point. Choose it
   in Target track, select media, then click **Add Selected Media to Track**.
   The dialog defaults to the entire source at the current playhead time;
   change source in/out and timeline start as needed. The engine validates
   media compatibility, bounds and overlap.
4. Select a timeline clip. Drag its body to move it or either edge to trim.
   **Move Clip** provides a numeric dialog. Trim by dragging a clip edge. **Razor**
   toggles the split tool and lights up blue while active. A vertical guide
   follows the pointer inside clips to show the split position; click to split. **Delete Clip**
   and **Undo** are also available as buttons.
5. Drag the ruler to scrub. The centered double-left and double-right
   playback controls move to the beginning and current project end. The
   play/pause control is disabled until playback is implemented. **Earlier**,
   **Later**, and **Zoom +/-** change the view. The black preview area
   currently displays the active clip name and timeline time. Decoded frames,
   thumbnails, playback and automatic proxy generation remain deferred.
6. Use **File > Save** to save to the current document.
   The first save asks for a location. **File > Save As** saves a separate
   `.fw` file and makes it the current document. The window title displays `Framewise` followed by the project name. New, Open and Exit ask before
   discarding changes; Cancel returns to the editor so they can be saved.
7. **Project Settings** edits the existing width, height and FPS settings.
   **Export Video** asks for an output path and uses the existing ffmpeg
   exporter. ffmpeg must be installed. Export runs synchronously, as before.

Keyboard shortcuts: Ctrl+N New, Ctrl+O Open, Ctrl+S Save,
Ctrl+Shift+S Save As, Ctrl+Z Undo, and Delete to remove a selected timeline
clip while the timeline has focus.

Media, track and clip identifiers are generated automatically and checked
against the current session. Menu actions automatically quote paths in the
commands they generate, including imports, project saves/opens and exports.
Spaces in paths are supported alongside letters, numbers, slashes,
backslashes, colons, dots, dashes and underscores. The shared `.fw` format
preserves double-quoted paths and accepts existing unquoted paths as well.
For example: `import media1 "C:\My Videos\take 1.mp4" 30 video`.

## Library boundary

- `ui/` depends on `Framewise` and `Framewise.Session` only. It does not
  invoke Timeline, Commands, Plan or Decode operations directly.
- Every edit builds a line internally and calls `Session.Execute`.
  Responses are shown in the status area; rejected edits redraw from the
  unchanged session. There is no parallel UI document model.
- Rendering reads `Sequence_Of` after execution. Selection, tools, zoom,
  scrolling and playhead are UI state and are not saved.
- Save and load retain the same `.fw` format as the CLI. No new backend
  commands or future media features are introduced by this layout change.

## Build and review

With the existing Alire/Adi2 and SDL3 dependencies installed (Linux also
requires a working SDL native file-dialog backend, such as a desktop portal
or Zenity):

```sh
cd ui
alr build
alr exec -- gprbuild -P ui_checks.gpr
./bin/timeline_view_tests
./bin/editor_split_tests
./bin/framewise_ui
```

Manual regression:

- Start empty; import media with an explicit duration, add a compatible
  track, and place the media. Verify invalid duration and overlapping
  placement display an error and leave the dialog open for correction.
- Move with both mouse and numeric dialog; trim with clip edges; split, delete and undo.
- Scrub a video gap and a clip; verify clip/time text changes, without
  adding an edit or marking the project dirty.
- Save a new project, edit and Save, then Save As. Reopen both files to
  verify their independent contents. Undo back to the saved state and
  verify New/Open no longer prompts to discard changes. Cancel the native Save/Open/Import dialogs
  and verify the current project is retained.
- Edit, then try New/Open/Exit. Cancel the discard prompt, save, and retry.
- Open `examples/cut.fw`, move c3 to 13.5 seconds, reject an overlapping
  move, and save `gui.fw`. Run the same load/moves/save in the CLI and
  compare the saved files. The documents must be identical.
- Export with actual example media available in the working directory and
  verify the resulting video. Check both successful and failed export.

## Automated regression baseline

Build the CLI once, then run all UI checks with assertions enabled:

```sh
cd cli
alr -n build
cd ../ui
alr -n build
alr -n exec -- gprbuild -P ui_checks.gpr
SDL_VIDEODRIVER=dummy SDL_RENDER_DRIVER=software ./bin/timeline_view_tests
SDL_VIDEODRIVER=dummy SDL_RENDER_DRIVER=software ./bin/editor_split_tests
python3 tests/run_regressions.py
```

These shell examples run from the repository root initially. On Windows,
set the SDL environment variables using PowerShell syntax. FFmpeg, ffprobe,
Python 3 and the usual UI build dependencies must be installed.

`timeline_view_tests` covers move/trim/split/delete/undo gestures, clipping,
zoom, playhead, rejected edits, cursor choices and the Razor split guide.
`editor_split_tests` covers both divider axes, drag bounds and small windows.
`run_regressions.py` adds the complete editor workflow: media filters, import
results, named tracks and validation, caret/focus, placement and move dialogs,
Razor selected state, navigation, settings, real export (including failure),
save/save-as and cancellation, native window titles, unsaved-change prompts,
routed divider dragging and routed scrollbar thumb/track interaction. Console
checks cover button placement, modal opening, a rendered caret, routed typing,
Enter/Run, errors, save/load bookkeeping, and transcript persistence.
It verifies the exported video with ffprobe and compares GUI and CLI saved
`.fw` documents byte for byte. Test files live in a disposable temporary folder.

The runner imports the production editor packages and calls
`Editor_Application.Initialize` before running `regression_scenarios.inc`,
then calls `Shutdown`. It exercises the same widgets and handlers as the app
without entering the interactive event loop or copying production source.
The behavioral scenarios remain the baseline established before the refactor.
No pixel screenshots are
required; layout checks assert relationships such as equal widths and centered
controls. File-picker result callbacks are tested; interaction with OS-native
file-picker windows and appearance on Windows/HiDPI remain manual checks.

CI imports the GUI job from main and runs the two widget suites plus this
workflow suite using SDL's dummy video driver and software rendering. The
library, CLI, export and proof jobs remain intact. On failure, CI uploads the
workflow log and generated regression driver to help locate the failed check.

## UI source organization

`src/framewise_ui.adb` is the executable entry point. The editor is organized by responsibility:

| Package | Responsibility |
| --- | --- |
| `Editor_Application` | Window startup, event loop, and cleanup |
| `Editor_Context` | Single backend session, widget handles, and shared UI state |
| `Editor_Controller` | Session commands, document lifecycle, and editor callbacks |
| `Editor_Console` | Floating command console, input focus, and command transcript |
| `Editor_Dialogs` | Form construction, input validation, and import results |
| `Editor_Layout` | Project files, preview, timeline controls, menus, and panel arrangement |
| `Editor_Styles` | Shared text, panel, button, and dropdown styles |
| `Editor_Widgets` | Common widget creation and callback wiring |
| `Editor_Cursors` | Pointer selection and native cursor resource cleanup |
| `Timeline_View` | Timeline drawing, selection, dragging, trimming, and Razor interaction |
| `Editor_Split` | Resizable panel layout and divider interaction |

The UI still submits document changes through `Framewise.Session.Execute`.
Shared context holds handles and transient editor state; the session remains
the source of truth for the project. Dialogs and the controller call each other
through their package interfaces, while layout only builds and connects widgets.

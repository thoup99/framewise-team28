# Framewise desktop editor

The editor uses a traditional layout inspired by OpenShot: a File menu at the top, Project Files on the left, Video Preview on the
right, and a full-width timeline below. No command entry or command history
panel is shown. The shared Session command protocol is an implementation
detail; users edit through menus, buttons, dialogs and timeline gestures.

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

When tracks exceed the timeline viewport, a vertical scrollbar appears on
its right edge. Drag the thumb, click the scrollbar track or use the wheel
to reach tracks below the viewport. It hides when all tracks fit.

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
against the current session. Paths currently must use letters, numbers,
slashes, backslashes, colons, dots, dashes and underscores. The shared `.fw`
format does not yet support quoted paths; the UI reports unsupported paths
instead of passing malformed arguments to the session. Paths containing
spaces are therefore not supported in this UI yet.

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

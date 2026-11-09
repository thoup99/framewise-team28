#!/usr/bin/env python3
"""Build a regression driver using the real editor packages and scenarios."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

UI = Path(__file__).resolve().parents[1]
REPO = UI.parent


def generate(destination):
    destination.mkdir(parents=True, exist_ok=True)
    source = """with Adi.Core; use Adi.Core;
with Adi.CSS_Styles; use Adi.CSS_Styles;
with Adi.Widget; use Adi.Widget;
with Adi.Widget_Styles; use Adi.Widget_Styles;
with Adi.Window; use Adi.Window;
with Framewise;
with Timeline_View;
with Editor_Split;
with Adi.Widget.Text_Editor;
with Adi.SDL.Events;
with Editor_Context; use Editor_Context;
with Adi.OS;
with Adi.SDL.Video;
with Interfaces.C.Strings;
with Ada.Characters.Latin_1;
with Ada.Strings.Fixed;
with Ada.Directories;
with Ada.Text_IO;
with Ada.Environment_Variables;
with Editor_Styles; use Editor_Styles;
with Editor_Controller; use Editor_Controller;
with Editor_Dialogs; use Editor_Dialogs;
with Editor_Application;
with Editor_Tooltips;
with Editor_Export;

procedure Framewise_UI_Regression is
   use type Buttons.Button_Handle;
   use type Labels.Label_Handle;
   use type Inputs.Text_Input_Handle;
   use type Combos.Combo_Box_Handle;
   use type Adi.Widget.Text_Editor.Text_Editor_Handle;
   use type Timeline_View.Views.Handle;
   use type Editor_Split.Views.Handle;
   use type US.Unbounded_String;
   use type Framewise.Time;
   use type Boxes.Box_Handle;
begin
   Editor_Application.Initialize;
"""
    source += (UI / 'tests/regression_scenarios.inc').read_text()
    source += '   Editor_Application.Shutdown;\nend Framewise_UI_Regression;\n'
    driver = destination / 'framewise_ui_regression.adb'
    if not driver.exists() or driver.read_text() != source:
        # GNAT timestamps have one-second resolution. Avoid stale code if
        # scenarios are edited and regenerated twice within the same second.
        for suffix in ('.o', '.ali'):
            (destination / 'obj' / ('framewise_ui_regression' + suffix)).unlink(missing_ok=True)
        driver.write_text(source)
    # JSON quoting is also valid for these absolute GPR path strings.
    (destination / 'regressions.gpr').write_text(f'''with "framewise";
with "adi.gpr";
project Regressions is
   for Source_Dirs use ({json.dumps((UI / 'src').as_posix())}, ".");
   for Object_Dir use "obj";
   for Exec_Dir use "bin";
   for Create_Missing_Dirs use "True";
   for Main use ("framewise_ui_regression.adb");
   package Compiler is
      for Default_Switches ("Ada") use ("-gnat2022", "-gnata", "-g");
   end Compiler;
   package Binder is
      for Switches ("Ada") use ("-Es");
   end Binder;
end Regressions;
''')


def run(args, **kwargs):
    print('+', ' '.join(map(str, args)), flush=True)
    return subprocess.run(args, check=True, timeout=180, **kwargs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--generate-only', type=Path,
                        help='Generate the adapter for a manually configured Ada toolchain.')
    parser.add_argument('--executable', type=Path, help='Run an already-built adapter.')
    parser.add_argument('--cli', type=Path, help='CLI executable for document round-trip comparison.')
    options = parser.parse_args()
    if options.generate_only:
        generate(options.generate_only.resolve())
        return
    build = UI / 'obj/regression-driver'
    if options.executable:
        executable = options.executable.resolve()
    else:
        generate(build)
        run(['alr', '-n', 'exec', '--', 'gprbuild', '-P', str(build / 'regressions.gpr')], cwd=UI)
        executable = build / 'bin/framewise_ui_regression'
    with tempfile.TemporaryDirectory(prefix='framewise-ui-regression-') as work:
        directory = Path(work)
        run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi', '-i',
             'color=c=blue:s=160x90:r=30', '-t', '3', '-c:v', 'mpeg4', str(directory / 'video clip.mp4')])
        environment = os.environ.copy()
        environment.setdefault('SDL_VIDEODRIVER', 'dummy')
        environment.setdefault('SDL_RENDER_DRIVER', 'software')
        environment['FRAMEWISE_TEST_DIR'] = work
        run([str(executable)], cwd=REPO, env=environment)
        result = subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries',
                  'format=duration:stream=width,height', '-of', 'json', str(directory / 'export final.mp4')],
                  text=True, timeout=30)
        probe = json.loads(result)
        assert 0 < float(probe['format']['duration']) < 10, probe
        assert any(s.get('width') == 320 and s.get('height') == 180 for s in probe['streams']), probe
        cli = options.cli.resolve() if options.cli else REPO / 'cli/bin/framewise_cli'
        run([str(cli), '-c', f'load {directory / "gui.fw"}', '-c', f'save {directory / "cli.fw"}'],
            cwd=REPO)
        assert (directory / 'gui.fw').read_bytes() == (directory / 'cli.fw').read_bytes(), \
            'GUI and CLI saved documents differ'
        print('PASS: real GUI export probed and GUI/CLI documents identical', flush=True)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Build a test-only adapter around the current monolithic editor.

The checked-in Ada scenarios exercise the real handlers/widgets. Only the app
entry point and event-loop call are replaced; production sources are untouched.
When the UI is split into packages, replace this adapter with package imports,
keeping the behavioral scenarios as the refactoring baseline.
"""
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
    source = (UI / 'src/framewise_ui.adb').read_text()
    for anchor in ('procedure Framewise_UI is', 'end Framewise_UI;', '      A.Run;'):
        if source.count(anchor) != 1:
            raise RuntimeError(f'UI test adapter needs updating: expected one {anchor!r}')
    source = source.replace('procedure Framewise_UI is', 'procedure Framewise_UI_Regression is')
    source = source.replace('end Framewise_UI;', 'end Framewise_UI_Regression;')
    source = source.replace('with Ada.Characters.Latin_1;',
                            'with Ada.Characters.Latin_1;\nwith Ada.Text_IO;\nwith Ada.Environment_Variables;')
    source = source.replace('      A.Run;', (UI / 'tests/regression_scenarios.inc').read_text())
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
             'color=c=blue:s=160x90:r=30', '-t', '3', '-c:v', 'mpeg4', str(directory / 'video.mp4')])
        environment = os.environ.copy()
        environment.setdefault('SDL_VIDEODRIVER', 'dummy')
        environment.setdefault('SDL_RENDER_DRIVER', 'software')
        environment['FRAMEWISE_TEST_DIR'] = work
        run([str(executable)], cwd=REPO, env=environment)
        result = subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries',
                  'format=duration:stream=width,height', '-of', 'json', str(directory / 'export.mp4')],
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

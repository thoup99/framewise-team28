#!/usr/bin/env python3
"""Exercise native export/proxy paths, including shell-special characters."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True, timeout=60)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('cli', type=Path)
    parser.add_argument('--jobs', type=Path, help='Exercise both export completion strategies')
    options = parser.parse_args()
    cli = options.cli.resolve()
    # Exercise both document quoting and shell quoting with the same paths.
    with tempfile.TemporaryDirectory(prefix='shell-paths-', dir=Path.cwd()) as work:
        root = Path(work)
        folder = root / "output files&cash$'folder"
        folder.mkdir()
        source = root / ("take 1&cash$'clip.mp4" if os.name == 'nt'
                         else "take 1&cash$'back\\slash.mp4")
        output = folder / 'render.mp4'
        run('ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi',
            '-i', 'color=c=blue:s=160x90:r=30', '-t', '0.4', '-c:v', 'mpeg4', str(source))
        result = run(str(cli), '-c', 'settings 320 180 30',
                     '-c', f'import source "{source}" 0.4 video', '-c', 'track v video',
                     '-c', 'place clip v source 0 0.4 0',
                     '-c', f'export "{output}"', '-c', 'proxy source',
                     '-c', f'save "{folder / "saved project.fw"}"',
                     '-c', f'load "{folder / "saved project.fw"}"')
        assert 'ok exported ' in result.stdout, result.stdout
        assert 'ok wrote ' in result.stdout, result.stdout
        assert output.is_file(), 'Export must use the requested directory and filename'
        assert Path(str(source) + '.proxy.mov').is_file(), 'Proxy must stay beside its source'
        if options.jobs:
            jobs = run(str(options.jobs.resolve()), str(source), str(folder / 'job'))
            print(jobs.stdout.strip())
            # Deterministic progress exercises partial writes, malformed values,
            # regressions, and progress=end arriving before the child exits.
            mock = root / 'mock-bin'
            mock.mkdir()
            script = mock / 'fake_ffmpeg.py'
            script.write_text(r"""import sys, time
from pathlib import Path
args = sys.argv[1:]
progress = Path(args[args.index('-progress') + 1])
with progress.open('w', newline='') as stream:
    stream.write('out_time_us=N/A\n' + 'out_time_us=-1\n' + 'out_time_us=200')
    stream.flush()
    time.sleep(0.08)
    stream.write('000\r\nprogress=continue\n')
    stream.flush()
    time.sleep(0.25)
    stream.write('out_time_us=100000\n' + 'out_time_us=' + '9' * 200 + '\n')
    stream.write('out_time_us=400000\nprogress=end\n')
    stream.flush()
    time.sleep(0.25)
try:
    Path(args[-1]).write_bytes(b'test export')
except OSError as error:
    print(error, file=sys.stderr)
    sys.exit(1)
""")
            if os.name == 'nt':
                (mock / 'ffmpeg.cmd').write_text(f'@"{sys.executable}" "{script}" %*\n')
            else:
                launcher = mock / 'ffmpeg'
                launcher.write_text(f'#!/bin/sh\nexec "{sys.executable}" "{script}" "$@"\n')
                launcher.chmod(0o755)
            environment = os.environ.copy()
            environment['PATH'] = str(mock) + os.pathsep + environment.get('PATH', '')
            environment['FRAMEWISE_EXPECT_PROGRESS'] = '1'
            subprocess.run([str(options.jobs.resolve()), str(source), str(folder / 'mock_job')],
                           env=environment, check=True, timeout=60)
        probe = json.loads(run('ffprobe', '-v', 'error', '-show_entries',
                               'format=duration:stream=width,height', '-of', 'json',
                               str(output)).stdout)
        assert abs(float(probe['format']['duration']) - 0.4) < 0.1, probe
        assert any(s.get('width') == 320 and s.get('height') == 180
                   for s in probe['streams']), probe
    print('PASS: native shell export/proxy preserve paths and exact output location')


if __name__ == '__main__':
    main()

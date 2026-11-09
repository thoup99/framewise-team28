#!/usr/bin/env python3
"""Exercise native export/proxy paths, including shell-special characters."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile


def run(*args):
    return subprocess.run(args, check=True, text=True, capture_output=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('cli', type=Path)
    options = parser.parse_args()
    cli = options.cli.resolve()
    # The document parser still splits on spaces. Keep the temporary root
    # space-free while exercising characters that shells would interpret.
    with tempfile.TemporaryDirectory(prefix='shell-paths-', dir=Path.cwd()) as work:
        root = Path(work)
        folder = root / "output&cash$'folder"
        folder.mkdir()
        source = root / ("take&cash$'clip.mp4" if os.name == 'nt'
                         else "take&cash$'back\\slash.mp4")
        output = folder / 'render.mp4'
        assert ' ' not in str(root), 'Run this regression from a path without spaces'
        run('ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi',
            '-i', 'color=c=blue:s=160x90:r=30', '-t', '0.4', '-c:v', 'mpeg4', str(source))
        result = run(str(cli), '-c', 'settings 320 180 30',
                     '-c', f'import source {source} 0.4 video', '-c', 'track v video',
                     '-c', 'place clip v source 0 0.4 0',
                     '-c', f'export {output}', '-c', 'proxy source')
        assert 'ok exported ' in result.stdout, result.stdout
        assert 'ok wrote ' in result.stdout, result.stdout
        assert output.is_file(), 'Export must use the requested directory and filename'
        assert Path(str(source) + '.proxy.mov').is_file(), 'Proxy must stay beside its source'
        probe = json.loads(run('ffprobe', '-v', 'error', '-show_entries',
                               'format=duration:stream=width,height', '-of', 'json',
                               str(output)).stdout)
        assert abs(float(probe['format']['duration']) - 0.4) < 0.1, probe
        assert any(s.get('width') == 320 and s.get('height') == 180
                   for s in probe['streams']), probe
    print('PASS: native shell export/proxy preserve paths and exact output location')


if __name__ == '__main__':
    main()

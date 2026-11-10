#!/usr/bin/env python3
"""Verify layout preferences using independent editor processes."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--executable', type=Path, required=True)
    options = parser.parse_args()
    executable = options.executable.resolve()
    with tempfile.TemporaryDirectory(prefix='framewise-layout-') as work:
        root = Path(work)
        preferences = root / 'preferences'
        environment = os.environ.copy()
        environment['FRAMEWISE_CONFIG_HOME'] = str(preferences)
        environment.setdefault('SDL_VIDEODRIVER', 'dummy')
        environment.setdefault('SDL_RENDER_DRIVER', 'software')

        def launch(mode):
            subprocess.run([str(executable), mode], env=environment, check=True, timeout=30)

        launch('write')
        layout = preferences / 'layout.conf'
        assert layout.is_file(), 'Closing the editor must write preferences'
        launch('read')
        for contents in ('invalid settings', 'framewise-layout-v1\n960\n',
                         'framewise-layout-v1\n960\n650\n1.5\n0.6\nFALSE\n',
                         'framewise-layout-v1\n-1\n650\n0.44\n0.6\nFALSE\n'):
            layout.write_text(contents)
            launch('defaults')
        layout.write_text('framewise-layout-v1\n960\n650\n0.44\n0.6\nTRUE\n')
        launch('maximized')
        layout.unlink()
        layout.mkdir()  # A directory at the settings filename cannot be read/written as a file.
        launch('defaults')
    print('PASS: layout survives relaunch; invalid/inaccessible settings use defaults')


if __name__ == '__main__':
    main()

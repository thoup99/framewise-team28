#!/usr/bin/env python3
"""Run from repository root after building tests.
Requires Pillow >= 10.2, a C compiler and libjpeg development files.
Reference uses nearest-neighbor chroma. Allow maximum channel error 3
(IDCT/color rounding) and mean error below 0.5.
"""
from pathlib import Path
import subprocess
import tempfile
from PIL import Image

root = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory() as directory:
    work = Path(directory)
    reference = work / "reference"
    subprocess.run(["cc", str(root / "jpeg_reference.c"), "-ljpeg", "-o", str(reference)],
                   check=True)
    for index in range(10):
        width, height = (35, 19) if index < 5 else (64, 48)
        image = Image.new("RGB", (width, height))
        image.putdata([((x * 3 + index * 10) % 256,
                        (y * 4 + index * 12) % 256, (x + y + index * 7) % 256)
                       for y in range(height) for x in range(width)])
        jpeg = work / f"{index}.jpg"
        image.save(jpeg, quality=90, subsampling=2,
                   restart_marker_blocks=2 if index % 2 else 0)
        rgba = work / f"{index}.rgba"
        with rgba.open("wb") as output:
            subprocess.run([str(reference), str(jpeg)], stdout=output, check=True)
        subprocess.run([str(root / "bin" / "jpeg_compare"), str(jpeg), str(rgba)],
                       check=True)

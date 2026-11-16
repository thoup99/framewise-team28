#!/usr/bin/env python3
"""Run from repository root after building tests.
Requires Pillow >= 10.2, a C compiler and libjpeg development files.
Reference uses the floating IDCT and nearest-neighbor chroma. Require
maximum channel error 2 and mean error below 0.5. Also compare five
540p frames from each of two ffmpeg-generated MJPEG proxies.
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

    # Exercise the actual 540p proxy format, rather than re-encoding frames
    # through Pillow. The two sources include moving detail and colour bars.
    for name, source in (("take1", "testsrc2"), ("take2", "smptebars")):
        proxy = work / f"{name}.proxy.mov"
        subprocess.run([
            "ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
            f"{source}=size=320x180:rate=5", "-frames:v", "5",
            "-vf", "scale=-2:540", "-c:v", "mjpeg", "-q:v", "3",
            "-pix_fmt", "yuvj420p", "-movflags", "+faststart", str(proxy),
        ], check=True)
        subprocess.run([
            "ffmpeg", "-v", "error", "-y", "-i", str(proxy),
            "-frames:v", "5", "-c:v", "copy", str(work / f"{name}-%d.jpg"),
        ], check=True)
        for number in range(1, 6):
            jpeg = work / f"{name}-{number}.jpg"
            rgba = jpeg.with_suffix(".rgba")
            with rgba.open("wb") as output:
                subprocess.run([str(reference), str(jpeg)], stdout=output, check=True)
            print(f"Comparing {name} proxy frame {number}/5", flush=True)
            # Robustness is covered above on small frames; mutating every
            # byte of full-size frames would make CI unnecessarily slow.
            subprocess.run([str(root / "bin" / "jpeg_compare"), str(jpeg),
                            str(rgba), "--pixels-only"], check=True)

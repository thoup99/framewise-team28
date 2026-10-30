#!/usr/bin/env python3
"""Inspect ffmpeg's copied MJPEG proxy frame without external Python packages.

Run after extracting frame.jpg with ffmpeg; this script verifies the
marker sequence and 4:2:0 baseline SOF0, and checks RGBA byte count.
"""
import argparse
from pathlib import Path


def inspect(path):
    data = Path(path).read_bytes()
    if data[:2] != b"\xff\xd8":
        raise ValueError("missing JPEG SOI")
    pos = 2
    markers = ["SOI"]
    width = height = None
    subsampling = None
    while pos < len(data):
        if data[pos] != 0xff:
            raise ValueError(f"expected marker at offset {pos}")
        while pos < len(data) and data[pos] == 0xff:
            pos += 1
        if pos >= len(data):
            raise ValueError("truncated marker")
        marker = data[pos]
        pos += 1
        markers.append(f"FF{marker:02X}")
        if marker == 0xda:  # SOS; following bytes are entropy-coded
            break
        if marker == 0xd9:
            break
        if marker in range(0xd0, 0xd8) or marker in (0xd8, 0x01):
            raise ValueError("unexpected stand-alone marker before SOS")
        if pos + 2 > len(data):
            raise ValueError("short segment length")
        size = int.from_bytes(data[pos:pos+2], "big")
        if size < 2 or pos + size > len(data):
            raise ValueError("segment extends beyond file")
        if marker == 0xc0:
            if size < 11:
                raise ValueError("short SOF0")
            precision = data[pos+2]
            height = int.from_bytes(data[pos+3:pos+5], "big")
            width = int.from_bytes(data[pos+5:pos+7], "big")
            components = data[pos+7]
            if size != 8 + 3 * components or components != 3 or precision != 8:
                raise ValueError("expected 8-bit three-component baseline SOF0")
            subsampling = tuple((data[pos+9+3*k] >> 4,
                                 data[pos+9+3*k] & 0xF)
                                for k in range(3))
            if subsampling != ((2, 2), (1, 1), (1, 1)):
                raise ValueError(f"expected 4:2:0, got {subsampling}")
        pos += size
    if width is None or height is None:
        raise ValueError("no SOF0 found")
    if "FFDA" not in markers:
        raise ValueError("no SOS found")
    print(f"PASS: JPEG {width}x{height}, 8-bit YCbCr 4:2:0")
    print("Markers before entropy-coded scan:", " ".join(markers))
    print("DQT segments:", markers.count("FFDB"))
    print("DHT segments:", markers.count("FFC4"))
    return width, height


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("jpeg")
    parser.add_argument("rgba")
    args = parser.parse_args()
    width, height = inspect(args.jpeg)
    got = Path(args.rgba).stat().st_size
    expected = width * height * 4
    if got != expected:
        raise SystemExit(f"FAIL: expected {expected} RGBA bytes, found {got}")
    print(f"PASS: reference RGBA has {got} bytes")


if __name__ == "__main__":
    main()

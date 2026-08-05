#!/usr/bin/env python3
"""Pack a set of PNG files into a Windows .ico file (no Pillow needed).

Usage: _pack_ico.py <dir> <size1> [size2 ...] <out.ico>

Each <dir>/<size>.png is embedded as a PNG-compressed icon entry. Modern
Windows (Vista+) reads PNG-format entries directly, and Go's rsrc / the
Windows shell both accept this form.
"""
import struct
import sys
import os


def main():
    if len(sys.argv) < 4:
        sys.exit("usage: _pack_ico.py <png-dir> <size1> [size2 ...] <out.ico>")
    png_dir = sys.argv[1]
    sizes = [int(s) for s in sys.argv[2:-1]]
    out_path = sys.argv[-1]

    images = []
    for sz in sizes:
        p = os.path.join(png_dir, f"{sz}.png")
        with open(p, "rb") as f:
            data = f.read()
        # ICO entry stores width/height as a single byte; 256 (and above) is
        # encoded as 0.
        w = 0 if sz >= 256 else sz
        images.append((w, len(data), data))

    count = len(images)
    # ICONDIR: reserved(2)=0, type(2)=1 (icon), count(2)
    header = struct.pack("<HHH", 0, 1, count)
    # Each ICONDIRENTRY is 16 bytes:
    #  width(1) height(1) colors(1)=0 reserved(1)=0
    #  planes(2)=1 bpp(2)=32 size(4) offset(4)
    entries = bytearray()
    blob = bytearray()
    offset = 6 + 16 * count  # header(6) + entries
    for w, size, data in images:
        entries += struct.pack("<BBBBHHII", w, w, 0, 0, 1, 32, size, offset)
        blob += data
        offset += size

    with open(out_path, "wb") as f:
        f.write(header)
        f.write(entries)
        f.write(blob)
    print(f"_pack_ico: wrote {out_path} ({6 + len(entries) + len(blob)} bytes, {count} images)")


if __name__ == "__main__":
    main()

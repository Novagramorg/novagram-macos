import re
import struct
import sys
import zlib


def read_rgba(path):
    match = re.search(r"-(\d+)x(\d+)\.rgba$", path)
    if not match:
        raise SystemExit(f"no WIDTHxHEIGHT suffix in {path}")
    width, height = int(match.group(1)), int(match.group(2))
    with open(path, "rb") as f:
        data = f.read()
    if len(data) != width * height * 4:
        raise SystemExit(f"{path}: expected {width * height * 4} bytes, got {len(data)}")
    return width, height, data


def write_png(path, width, height, rgba):
    rows = b"".join(b"\x00" + rgba[y * width * 4:(y + 1) * width * 4] for y in range(height))
    def chunk(kind, payload):
        body = kind + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(rows, 6))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def main():
    if len(sys.argv) < 3:
        raise SystemExit("usage: compare_rgba.py baseline.rgba candidate.rgba [out-prefix]")
    w0, h0, a = read_rgba(sys.argv[1])
    w1, h1, b = read_rgba(sys.argv[2])
    if (w0, h0) != (w1, h1):
        raise SystemExit(f"size mismatch {w0}x{h0} vs {w1}x{h1}")
    total = 0
    worst = 0
    over8 = 0
    diff = bytearray(len(a))
    for i in range(0, len(a), 4):
        d = max(abs(a[i] - b[i]), abs(a[i + 1] - b[i + 1]), abs(a[i + 2] - b[i + 2]))
        total += abs(a[i] - b[i]) + abs(a[i + 1] - b[i + 1]) + abs(a[i + 2] - b[i + 2])
        if d > worst:
            worst = d
        if d > 8:
            over8 += 1
        v = min(255, d * 8)
        diff[i] = v
        diff[i + 1] = v
        diff[i + 2] = v
        diff[i + 3] = 255
    pixels = w0 * h0
    print(f"{w0}x{h0} meanAbsDiff={total / (pixels * 3):.3f} maxDiff={worst} pixelsOver8={over8 * 100.0 / pixels:.3f}%")
    if len(sys.argv) > 3:
        prefix = sys.argv[3]
        write_png(prefix + "-baseline.png", w0, h0, a)
        write_png(prefix + "-candidate.png", w0, h0, b)
        write_png(prefix + "-diff.png", w0, h0, bytes(diff))


if __name__ == "__main__":
    main()

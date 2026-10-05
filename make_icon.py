"""Write assets/icon.png (512x512 RGB) for the Windows/Android packages."""
import os
import struct
import zlib

SIZE = 512
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "icon.png")


def _pixel(x, y):
    nx = (x / (SIZE - 1)) * 2.0 - 1.0
    ny = 1.0 - (y / (SIZE - 1)) * 2.0
    # Dark asphalt with a slight vignette.
    vig = 1.0 - min(1.0, (nx * nx + ny * ny) * 0.55)
    r = int(18 * vig)
    g = int(22 * vig)
    b = int(28 * vig)
    # Olive ring (NFSMW-ish).
    d = (nx * nx + ny * ny) ** 0.5
    if 0.72 < d < 0.88:
        return 168, 176, 92
    # Chevron / hood silhouette pointing up.
    if -0.38 < nx < 0.38 and -0.42 < ny < 0.55:
        body = abs(nx) < 0.22 + 0.18 * (0.55 - ny) / 0.97
        cabin = abs(nx) < 0.14 and 0.08 < ny < 0.42
        if body and not cabin:
            return 210, 214, 120
        if cabin:
            return 40, 48, 58
    # Headlight dots.
    for hx, hy in ((-0.16, -0.28), (0.16, -0.28)):
        if (nx - hx) ** 2 + (ny - hy) ** 2 < 0.012:
            return 240, 240, 220
    return r, g, b


def write_png(path, size=SIZE):
    raw = bytearray()
    for y in range(size):
        raw.append(0)
        for x in range(size):
            raw.extend(_pixel(x, y))

    def chunk(tag, data):
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))
    print("wrote", path, os.path.getsize(path), "bytes")


if __name__ == "__main__":
    write_png(OUT)

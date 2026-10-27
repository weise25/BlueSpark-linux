#!/usr/bin/env python3
"""Extracts an Xbox 360 disc image (XDVDFS/XGD: a redump image or a trimmed XISO) into a folder, as extract-xiso does.

    xiso_extract.py <image.iso> <folder>
"""
import os, struct, sys

SECTOR = 2048
MAGIC = b'MICROSOFT*XBOX*MEDIA'
# Where the game partition starts in the image: a trimmed XISO, XGD3, XGD2, XGD1.
PARTITION_OFFSETS = (0, 0x2080000, 0xFD90000, 0x18300000)


def find_partition(f):
    for base in PARTITION_OFFSETS:
        f.seek(base + 32 * SECTOR)
        if f.read(len(MAGIC)) == MAGIC:
            return base
    raise SystemExit('Not an Xbox disc image (no XDVDFS header found).')


def safe_name(name):
    if name in ('', '.', '..') or '/' in name or '\\' in name or '\0' in name:
        raise SystemExit(f'A file in the image has a bad name: {name!r}')
    return name


def walk(f, base, sector, size, out, files):
    f.seek(base + sector * SECTOR)
    table = f.read(size)
    pending = [0]
    seen = set()
    while pending:
        off = pending.pop()
        if off in seen or off + 14 > len(table):
            continue
        seen.add(off)
        left, right, start, length, attrs, name_len = struct.unpack_from('<HHIIBB', table, off)
        if left == 0xFFFF and right == 0xFFFF:   # (padding at a sector's end)
            continue
        name = safe_name(table[off + 14:off + 14 + name_len].decode('latin-1'))
        if left:
            pending.append(left * 4)
        if right:
            pending.append(right * 4)
        path = os.path.join(out, name)
        if attrs & 0x10:
            os.makedirs(path, exist_ok=True)
            if length:
                walk(f, base, start, length, path, files)
        else:
            files.append((path, base + start * SECTOR, length))


def main():
    image, out = sys.argv[1], sys.argv[2]
    with open(image, 'rb') as f:
        base = find_partition(f)
        f.seek(base + 32 * SECTOR + len(MAGIC))
        root_sector, root_size = struct.unpack('<II', f.read(8))
        os.makedirs(out, exist_ok=True)
        files = []
        walk(f, base, root_sector, root_size, out, files)
        total = sum(n for _, _, n in files)
        done = 0
        for path, at, length in files:
            f.seek(at)
            with open(path, 'wb') as w:
                left = length
                while left:
                    chunk = f.read(min(left, 8 << 20))
                    if not chunk:
                        raise SystemExit(f'The image ends early (in {path}).')
                    w.write(chunk)
                    left -= len(chunk)
                    done += len(chunk)
            # (A percentage line per file, for a progress bar.)
            print(f'{done * 100 // max(total, 1)}', flush=True)
        print(f'# {len(files)} files, {total} bytes', flush=True)


if __name__ == '__main__':
    main()

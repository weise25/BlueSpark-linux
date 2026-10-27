#!/usr/bin/env python3
"""Adds (or updates) a non-Steam game in every Steam account's shortcuts.vdf on this PC, with its pictures in the
account's grid folder. Steam must be closed: it rewrites the file from memory when it exits.

    steam_shortcut.py --steam <Steam folder> --name <name> --exe <program> --start-dir <folder>
                      [--icon <png>] [--hero <image>] [--header <image>]
"""
import argparse, os, shutil, zlib


def read_vdf(data):
    # Binary VDF: 0x00 map, 0x01 string, 0x02 int32, 0x08 end of map; keys and strings NUL-terminated.
    pos = 0

    def cstr():
        nonlocal pos
        end = data.index(b'\0', pos)
        s = data[pos:end].decode('utf-8', 'replace')
        pos = end + 1
        return s

    def read_map():
        nonlocal pos
        m = {}
        while True:
            t = data[pos]; pos += 1
            if t == 0x08:
                return m
            key = cstr()
            if t == 0x00:
                m[key] = read_map()
            elif t == 0x01:
                m[key] = cstr()
            elif t == 0x02:
                m[key] = int.from_bytes(data[pos:pos + 4], 'little', signed=True); pos += 4
            else:
                raise ValueError(f'unknown VDF type {t:#x}')

    if not data:
        return {'shortcuts': {}}
    return read_map()


def write_vdf(m):
    out = bytearray()
    for k, v in m.items():
        if isinstance(v, dict):
            out += b'\x00' + k.encode() + b'\0' + write_vdf(v)
        elif isinstance(v, int):
            out += b'\x02' + k.encode() + b'\0' + (v & 0xFFFFFFFF).to_bytes(4, 'little')
        else:
            out += b'\x01' + k.encode() + b'\0' + str(v).encode() + b'\0'
    return bytes(out) + b'\x08'


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--steam', required=True)
    p.add_argument('--name', required=True)
    p.add_argument('--exe', required=True)
    p.add_argument('--start-dir', required=True)
    p.add_argument('--icon', default='')
    p.add_argument('--hero', default='')
    p.add_argument('--header', default='')
    a = p.parse_args()

    exe = f'"{a.exe}"'
    # The id Steam gives a non-Steam game (its grid pictures are named by it).
    appid = zlib.crc32((exe + a.name).encode()) | 0x80000000
    entry = {
        'appid': appid, 'AppName': a.name, 'Exe': exe, 'StartDir': f'"{a.start_dir}"', 'icon': a.icon,
        'ShortcutPath': '', 'LaunchOptions': '', 'IsHidden': 0, 'AllowDesktopConfig': 1, 'AllowOverlay': 1,
        'OpenVR': 0, 'Devkit': 0, 'DevkitGameID': '', 'DevkitOverrideAppID': 0, 'LastPlayTime': 0,
        'FlatpakAppID': '', 'tags': {},
    }
    users = os.path.join(a.steam, 'userdata')
    done = 0
    for user in sorted(os.listdir(users)) if os.path.isdir(users) else []:
        if not user.isdigit() or user == '0':
            continue
        config = os.path.join(users, user, 'config')
        os.makedirs(config, exist_ok=True)
        path = os.path.join(config, 'shortcuts.vdf')
        root = read_vdf(open(path, 'rb').read()) if os.path.exists(path) else {'shortcuts': {}}
        shortcuts = root.setdefault('shortcuts', {})
        key = next((k for k, s in shortcuts.items()
                    if s.get('AppName') == a.name or s.get('Exe') == exe), None)
        if key is None:
            key = str(max([int(k) for k in shortcuts if k.isdigit()] + [-1]) + 1)
        else:
            # (Kept: what Steam or the player set on it.)
            for k in ('LastPlayTime', 'tags', 'LaunchOptions', 'IsHidden'):
                if k in shortcuts[key]:
                    entry[k] = shortcuts[key][k]
        shortcuts[key] = dict(entry)
        if os.path.exists(path):
            shutil.copyfile(path, path + '.bak-bluespark')
        with open(path + '.part', 'wb') as f:
            f.write(write_vdf(root))
        os.replace(path + '.part', path)
        grid = os.path.join(config, 'grid')
        os.makedirs(grid, exist_ok=True)
        for src, suffix in ((a.hero, '_hero'), (a.header, ''), (a.icon, '_icon')):
            if src and os.path.exists(src):
                shutil.copyfile(src, os.path.join(grid, f'{appid}{suffix}{os.path.splitext(src)[1]}'))
        done += 1
    print(f'added to {done} Steam account(s)')
    return 0 if done else 1


if __name__ == '__main__':
    raise SystemExit(main())

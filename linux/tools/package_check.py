#!/usr/bin/env python3
"""Checks a TTT2 playtest package zip as Start Here does on Windows (rex/tools/package-check.ps1, Test-ReleaseZip):
no entry outside its folder, the owner's ECDSA P-256 signature over its file list (rex/package-signature.txt), every
file as listed. The signature is checked with the openssl command.

    package_check.py <zip>      prints "ok <track> <patch>" and exits 0, or prints why not and exits 1
"""
import base64, hashlib, os, subprocess, sys, tempfile, zipfile

PUBLIC_KEY = 'RUNTMSAAAABLKNbE41jshACRu1ti3dBO8x2HO2e44EqGeEmGDsbVqlHyFMnnESlIX0WCVCt+YyZDZaGYA5FGPpVGe//LRVVG'
SIGNATURE_ENTRY = 'rex/package-signature.txt'
NOT_OFFICIAL = "This isn't an official TTT2 playtest package."


def spki_pem(blob):
    # A BCRYPT_ECCPUBLIC_BLOB ("ECS1", 32, X, Y) as a P-256 SubjectPublicKeyInfo.
    if blob[:4] != b'ECS1' or int.from_bytes(blob[4:8], 'little') != 32:
        raise ValueError('not a P-256 public key blob')
    der = bytes.fromhex('3059301306072a8648ce3d020106082a8648ce3d030107034200') + b'\x04' + blob[8:72]
    body = base64.encodebytes(der).decode()
    return '-----BEGIN PUBLIC KEY-----\n' + body + '-----END PUBLIC KEY-----\n'


def der_signature(raw):
    # .NET's ECDsa signs as r || s; openssl reads DER.
    def integer(b):
        b = b.lstrip(b'\x00') or b'\x00'
        if b[0] & 0x80:
            b = b'\x00' + b
        return b'\x02' + bytes([len(b)]) + b
    half = len(raw) // 2
    body = integer(raw[:half]) + integer(raw[half:])
    return b'\x30' + bytes([len(body)]) + body


def verify(text, signature):
    with tempfile.TemporaryDirectory() as d:
        paths = {n: os.path.join(d, n) for n in ('key.pem', 'sig.der', 'data')}
        with open(paths['key.pem'], 'w') as f:
            f.write(spki_pem(base64.b64decode(PUBLIC_KEY)))
        with open(paths['sig.der'], 'wb') as f:
            f.write(der_signature(signature))
        with open(paths['data'], 'wb') as f:
            f.write(text.encode('utf-8'))
        r = subprocess.run(['openssl', 'dgst', '-sha256', '-verify', paths['key.pem'], '-signature', paths['sig.der'],
                            paths['data']], capture_output=True)
        return r.returncode == 0


def check(path):
    try:
        z = zipfile.ZipFile(path)
    except Exception:
        return None, f"{os.path.basename(path)} isn't a zip file that opens."
    names = [i.filename for i in z.infolist()]
    for n in names:
        n2 = n.replace('\\', '/')
        if n2.startswith('/') or (len(n2) > 1 and n2[1] == ':') or '..' in n2.split('/'):
            return None, f'{NOT_OFFICIAL} (It has files that would land outside its folder: {n}.)'
    def find(suffix):
        for n in names:
            parts = n.split('/', 1)
            if len(parts) == 2 and parts[1] == suffix:
                return z.read(n).decode('utf-8-sig')
        return None
    info_text = find('rex/package-info.txt')
    if info_text is None:
        return None, f"{os.path.basename(path)} isn't a TTT2 Native package."
    info = {'track': 'main', 'patch': '0'}
    for line in info_text.splitlines():
        if '=' in line:
            k, v = line.split('=', 1)
            info[k.strip()] = v.strip()
    sig_text = find(SIGNATURE_ENTRY)
    if sig_text is None:
        return None, f"{NOT_OFFICIAL} (It isn't signed.)"
    lines = [l for l in sig_text.splitlines() if l != '']
    if len(lines) < 3 or lines[0] != 'TTT2 signed package 1' or not lines[-1].startswith('signature '):
        return None, f'{NOT_OFFICIAL} (Its signature file is damaged.)'
    signed = lines[:-1]
    if not verify('\r\n'.join(signed) + '\r\n', base64.b64decode(lines[-1].split(' ', 1)[1])):
        return None, f"{NOT_OFFICIAL} (Its signature doesn't match.)"
    actual = []
    for i in z.infolist():
        if i.filename.endswith('/'):
            continue
        rel = i.filename.split('/', 1)[1] if '/' in i.filename else ''
        if rel == SIGNATURE_ENTRY:
            continue
        actual.append(f'{hashlib.sha256(z.read(i)).hexdigest()} {i.filename}')
    # (PowerShell's Sort-Object -CaseSensitive is not an ordinal sort: compared as sets, as Compare-Object does.)
    listed = signed[1:]
    if sorted(listed) != sorted(actual):
        diff = sorted(set(listed) ^ set(actual))
        return None, f"{NOT_OFFICIAL} (A file in it was changed, added or removed: {diff[0].split(' ', 1)[1]}.)"
    return info, None


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--signature-only':
        # (A check of an unpacked package's own signature file: the signature over its list, not the files.)
        lines = [l for l in open(sys.argv[2], encoding='utf-8-sig').read().splitlines() if l]
        ok = verify('\r\n'.join(lines[:-1]) + '\r\n', base64.b64decode(lines[-1].split(' ', 1)[1]))
        print('ok' if ok else 'bad')
        sys.exit(0 if ok else 1)
    info, why = check(sys.argv[1])
    if why:
        print(why)
        sys.exit(1)
    print(f"ok {info.get('track')} {info.get('patch')}")

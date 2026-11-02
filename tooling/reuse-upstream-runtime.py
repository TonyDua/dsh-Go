#!/usr/bin/env python3
"""Stage the unchanged arm64 runtime from the pinned upstream 1.0.9 release."""
import hashlib
import json
import sys
from pathlib import Path
from zipfile import ZipFile

APK_SHA256 = '6b8543694b46a44f7c25010c8ef2afbccc1636955b89bbc8d7b6fee995c9d5a1'
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'runtime/out/arm64-v8a'


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as src:
        for chunk in iter(lambda: src.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def main():
    apk = Path(sys.argv[1])
    if digest(apk) != APK_SHA256:
        raise SystemExit('Upstream APK SHA-256 mismatch')
    with ZipFile(apk) as z:
        manifest = json.loads(z.read('assets/runtime/manifest.json'))
        rootfs = manifest['rootfs']
        expected_libs = {'libproot.so', 'libproot-loader.so', 'libtalloc.so', 'libandroid-shmem.so'}
        if rootfs != 'rootfs-arm64-v8a.tar.xz' or set(manifest['jniLibs']) != expected_libs:
            raise SystemExit('Unexpected upstream runtime manifest')
        assets = ['assets/runtime/manifest.json', 'assets/runtime/' + rootfs]
        assets += [n for n in z.namelist() if n.startswith('assets/runtime/licenses/') and not n.endswith('/')]
        for name in assets:
            relative = Path(name).relative_to('assets')
            if '..' in relative.parts:
                raise SystemExit('Invalid asset path')
            target = OUT / 'assets' / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            with z.open(name) as src, target.open('wb') as dst:
                while chunk := src.read(1024 * 1024):
                    dst.write(chunk)
        if digest(OUT / 'assets/runtime' / rootfs) != manifest['rootfsSha256']:
            raise SystemExit('Runtime rootfs SHA-256 mismatch')
        for name in sorted(expected_libs):
            target = OUT / 'jniLibs/arm64-v8a' / name
            target.parent.mkdir(parents=True, exist_ok=True)
            with z.open('lib/arm64-v8a/' + name) as src, target.open('wb') as dst:
                dst.write(src.read())
            if digest(target) != manifest['jniLibs'][name]['sha256']:
                raise SystemExit(f'Runtime library SHA-256 mismatch: {name}')
    print('Verified and staged upstream 1.0.9 arm64 runtime:', manifest['runtimeVersion'])


if __name__ == '__main__':
    main()

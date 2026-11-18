# -*- coding: utf-8 -*-
"""Распаковка war3_assets_NN.pak (из extract_war3.gd) в папку: python unpak.py <папка с .pak> <куда>"""
import glob
import os
import struct
import sys


def main():
    src, dst = sys.argv[1], sys.argv[2]
    n = 0
    for p in sorted(glob.glob(os.path.join(src, 'war3_assets_*.pak'))):
        b = open(p, 'rb').read()
        i = 0
        while i + 2 <= len(b):
            ln = struct.unpack_from('<H', b, i)[0]
            i += 2
            path = b[i:i + ln].decode('utf-8')
            i += ln
            sz = struct.unpack_from('<I', b, i)[0]
            i += 4
            data = b[i:i + sz]
            i += sz
            out = os.path.join(dst, *path.lower().replace('/', '\\').split('\\'))
            os.makedirs(os.path.dirname(out), exist_ok=True)
            open(out, 'wb').write(data)
            n += 1
    print('files', n)


if __name__ == '__main__':
    main()

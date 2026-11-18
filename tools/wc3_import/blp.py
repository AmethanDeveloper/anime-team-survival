# -*- coding: utf-8 -*-
"""BLP (текстуры Warcraft 3) -> PIL RGBA с правильной прозрачностью.

Pillow читает BLP1 со сжатием JPEG без альфа-канала (всё непрозрачно) — а у эффектов WC3 именно в нём форма
частиц и свечений. Здесь JPEG собирается из общего заголовка и первого мип-уровня и декодируется как
4-канальный (B, G, R, A без инверсии).
"""
import io
import struct

from PIL import Image


def open_image(data):
    if data[:4] == b'BLP1':
        comp, alpha_bits, w, h = struct.unpack_from('<IIII', data, 4)
        if comp == 0:
            offs = struct.unpack_from('<16I', data, 28)
            sizes = struct.unpack_from('<16I', data, 92)
            hsize = struct.unpack_from('<I', data, 156)[0]
            head = data[160:160 + hsize]
            jpg = head + data[offs[0]:offs[0] + sizes[0]]
            im = Image.open(io.BytesIO(jpg))
            im.draft(None, None)
            im.load()
            if im.mode == 'CMYK':
                # Pillow отдаёт 4-канальный JPEG инвертированным (соглашение Adobe) — возвращаем как было
                from PIL import ImageChops
                b, g, r, a = (ImageChops.invert(c) for c in im.split())
                if not alpha_bits:
                    a = Image.new('L', im.size, 255)
                out = Image.merge('RGBA', (r, g, b, a))
            else:
                out = im.convert('RGBA')
            if out.size != (w, h):
                out = out.crop((0, 0, w, h))
            return out
        if comp == 1:
            # палитра 256 цветов (BGRA) + индексы + отдельная альфа (Pillow её не читает)
            import numpy as np
            offs = struct.unpack_from('<16I', data, 28)
            pal = np.frombuffer(data, dtype=np.uint8, count=1024, offset=156).reshape(256, 4)
            n = w * h
            o = offs[0]
            idx = np.frombuffer(data, dtype=np.uint8, count=n, offset=o)
            rgb = pal[idx][:, [2, 1, 0]]
            if alpha_bits == 8:
                a = np.frombuffer(data, dtype=np.uint8, count=n, offset=o + n)
            elif alpha_bits in (1, 4):
                bits = np.unpackbits(np.frombuffer(data, dtype=np.uint8, count=(n * alpha_bits + 7) // 8,
                                                   offset=o + n), bitorder='little')
                if alpha_bits == 1:
                    a = bits[:n] * 255
                else:
                    a = (bits[:n * 4].reshape(-1, 4) * np.array([1, 2, 4, 8])).sum(1) * 17
                a = a.astype(np.uint8)
            else:
                a = np.full(n, 255, np.uint8)
            arr = np.concatenate([rgb, a[:, None]], axis=1).reshape(h, w, 4)
            return Image.fromarray(arr.astype(np.uint8), 'RGBA')
    im = Image.open(io.BytesIO(data))
    im.load()
    return im

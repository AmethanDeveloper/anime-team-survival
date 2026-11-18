# -*- coding: utf-8 -*-
"""Упаковка эффектов и звуков для игры: десятки сотен файлов -> несколько .pak + один JSON.

  w3_fx.json    — {"index": путь WC3 -> имя, "models": имя -> данные fx.json, "files": имя файла -> [пак, смещение, размер]}
  w3_fx_N.pak   — GLB-модели и текстуры частиц подряд (до ~25 МБ на файл)
  w3_sounds.pak — звуки, их места — в w3_data.json["sound_files"]
Игра читает их сама (GLTFDocument, Image.load_png_from_buffer, AudioStreamMP3), импорт в редакторе не нужен.

Запуск: python pack_w3.py <папка fx> <папка sounds> <w3_data.json> <куда>
"""
import json
import os
import sys

LIMIT = 25_000_000
HEADER = b'W3PAK\x00\x01\x00' + b'\x00' * 8


def pack(files, out_dir, prefix):
    table = {}
    n = 0
    f = None
    for name, path in files:
        data = open(path, 'rb').read()
        if f is None or f.tell() + len(data) > LIMIT:
            if f:
                f.close()
            fn = '%s_%d.pak' % (prefix, n)
            f = open(os.path.join(out_dir, fn), 'wb')
            # свой заголовок: без него файл, начинающийся с PNG/MP3, принимают за картинку/звук и дописывают метаданные
            f.write(HEADER)
            n += 1
        table[name] = [fn, f.tell(), len(data)]
        f.write(data)
    if f:
        f.close()
    return table


def main():
    fx_dir, snd_dir, data_json, out = sys.argv[1:5]
    os.makedirs(out, exist_ok=True)
    for old in os.listdir(out):
        if old.startswith(('w3_fx_', 'w3_sounds_')) and old.endswith('.pak'):
            os.remove(os.path.join(out, old))
    index = json.load(open(os.path.join(fx_dir, 'index.json')))
    models = {}
    files = []
    for fn in sorted(os.listdir(fx_dir)):
        p = os.path.join(fx_dir, fn)
        if fn.endswith('.fx.json'):
            models[fn[:-8]] = json.load(open(p))
        elif fn.endswith(('.glb', '.png')):
            files.append((fn, p))
    table = pack(files, out, 'w3_fx')
    json.dump({'index': index, 'models': models, 'files': table}, open(os.path.join(out, 'w3_fx.json'), 'w'),
              separators=(',', ':'))
    data = json.load(open(data_json, encoding='utf-8'))
    snd = [(fn, os.path.join(snd_dir, fn)) for fn in sorted(os.listdir(snd_dir)) if not fn.endswith('.import')]
    stable = pack(snd, out, 'w3_sounds')
    data['sound_files'] = stable
    json.dump(data, open(os.path.join(out, 'w3_data.json'), 'w', encoding='utf-8'), ensure_ascii=False,
              separators=(',', ':'))
    print('models', len(models), 'fx files', len(table), 'sounds', len(stable),
          sorted({v[0] for v in list(table.values()) + list(stable.values())}))


if __name__ == '__main__':
    main()

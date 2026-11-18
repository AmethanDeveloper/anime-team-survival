# -*- coding: utf-8 -*-
"""Модель Warcraft 3 (.mdx) -> model.glb для game/heroes/<герой>/ (+ hero.json с ростом и анимациями).

Запуск:
    python convert_model.py <модель.mdx> <папка героя> [папка с текстурами .blp]

Текстуры ищутся по путям из модели внутри папки с текстурами (по умолчанию — рядом с моделью),
например war3mapImported\\hero.blp -> <папка>\\war3mapImported\\hero.blp или просто <папка>\\hero.blp.
Стандартные текстуры Warcraft (Textures\\*.blp — свечения, шлейфы) обычно не нужны: части с ними пропускаются.
Нужен Python 3 с Pillow и numpy: pip install pillow numpy
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import mdx2gltf  # noqa: E402
from anims import choose  # noqa: E402


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    src, out_dir = sys.argv[1], sys.argv[2]
    tex_dir = sys.argv[3] if len(sys.argv) > 3 else os.path.dirname(os.path.abspath(src))
    cache = {}

    def read_file(path):
        if path in cache:
            return cache[path]
        data = None
        parts = path.replace('\\', '/').split('/')
        for cand in (os.path.join(tex_dir, *parts), os.path.join(tex_dir, parts[-1])):
            if os.path.isfile(cand):
                data = open(cand, 'rb').read()
                break
        cache[path] = data
        return data

    os.makedirs(out_dir, exist_ok=True)
    glb = os.path.join(out_dir, 'model.glb')
    info = mdx2gltf.convert(open(src, 'rb').read(), read_file, glb)
    anims = choose(info['anims'], info['body_vis'], info['durations'], None, info['height'])
    cfg = {"model_height": round(info['height'], 3), "scale": 1.0, "ground": True, "rotate_y": 0,
           "animations": anims, "source": os.path.basename(src)}
    cfg_path = os.path.join(out_dir, 'hero.json')
    if os.path.isfile(cfg_path):
        old = json.load(open(cfg_path, encoding='utf-8'))
        old.update({k: cfg[k] for k in ("model_height", "ground", "animations", "source")})
        cfg = old
    json.dump(cfg, open(cfg_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    print('Готово: %s (%d КБ), частей %d, анимаций %d' % (glb, os.path.getsize(glb) // 1024, info['geosets'], len(info['anims'])))
    print('Анимации в игре:', anims)
    missing = sorted(p for p, d in cache.items() if d is None)
    if missing:
        print('Не найдены текстуры (части с ними пропущены):', ', '.join(missing))


if __name__ == '__main__':
    main()

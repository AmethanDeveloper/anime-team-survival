# -*- coding: utf-8 -*-
"""Модели эффектов Warcraft 3 (.mdx) -> <ключ>.glb + <ключ>.fx.json (+ текстуры частиц) для W3Model в Godot.

fx.json:
  anims:    {имя: [длительность_с, зациклена]}  — имена как в GLB
  emitters: частицы PRE2 — параметры, текстура, путь узла по анимациям (позиция/поворот), ключи частоты/видимости
  ribbons:  ленты RIBB — то же для шлейфов
Запуск: python fx_convert.py <models_needed.json> <выход> [папка с базовыми файлами Warcraft]
"""
import io
import json
import os
import re
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, '/home/claude/work/scripts')
import mdx  # noqa: E402
import mdx2gltf  # noqa: E402
import pose  # noqa: E402

SCALE = mdx2gltf.SCALE
FPS = 15.0


def safe_name(key):
    return re.sub(r'[^a-z0-9_]+', '_', key.lower()).strip('_')[:80]


def conv(v):
    return [float(v[1]) * SCALE, float(v[2]) * SCALE, float(v[0]) * SCALE]


def mat_to_quat(m):
    """3x3 -> кватернион (x, y, z, w) в осях glTF."""
    # перестановка осей WC3 -> glTF: P * M * P^T, P: (x,y,z)->(y,z,x)
    P = np.array([[0, 1, 0], [0, 0, 1], [1, 0, 0]], dtype=float)
    R = P @ m @ P.T
    # убираем масштаб
    for i in range(3):
        n = np.linalg.norm(R[:, i])
        if n > 1e-6:
            R[:, i] /= n
    t = R[0, 0] + R[1, 1] + R[2, 2]
    if t > 0:
        s = (t + 1.0) ** 0.5 * 2
        w, x, y, z = 0.25 * s, (R[2, 1] - R[1, 2]) / s, (R[0, 2] - R[2, 0]) / s, (R[1, 0] - R[0, 1]) / s
    elif R[0, 0] > R[1, 1] and R[0, 0] > R[2, 2]:
        s = (1.0 + R[0, 0] - R[1, 1] - R[2, 2]) ** 0.5 * 2
        w, x, y, z = (R[2, 1] - R[1, 2]) / s, 0.25 * s, (R[0, 1] + R[1, 0]) / s, (R[0, 2] + R[2, 0]) / s
    elif R[1, 1] > R[2, 2]:
        s = (1.0 + R[1, 1] - R[0, 0] - R[2, 2]) ** 0.5 * 2
        w, x, y, z = (R[0, 2] - R[2, 0]) / s, (R[0, 1] + R[1, 0]) / s, 0.25 * s, (R[1, 2] + R[2, 1]) / s
    else:
        s = (1.0 + R[2, 2] - R[0, 0] - R[1, 1]) ** 0.5 * 2
        w, x, y, z = (R[1, 0] - R[0, 1]) / s, (R[0, 2] + R[2, 0]) / s, (R[1, 2] + R[2, 1]) / s, 0.25 * s
    return [round(float(x), 4), round(float(y), 4), round(float(z), 4), round(float(w), 4)]


def anim_names(M):
    used = {}
    out = []
    for s in M['sequences']:
        nm = mdx2gltf.clean_name(s['name'])
        c = used.get(nm.lower(), 0)
        used[nm.lower()] = c + 1
        out.append(nm if not c else '%s %d' % (nm, c + 1))
    return out


def track_keys(M, tr, seq):
    """Ключи скалярной дорожки внутри последовательности: [[t_c, v], ...] (глобальная — с пометкой)."""
    if tr is None:
        return None
    if tr['gs'] is not None:
        gd = M['globalseqs'][tr['gs']] if tr['gs'] < len(M['globalseqs']) else 0
        return {'global': gd / 1000.0, 'keys': [[k[0] / 1000.0, float(k[1][0])] for k in tr['keys']]}
    st, en = seq['start'], seq['end']
    ks = [[(k[0] - st) / 1000.0, float(k[1][0])] for k in tr['keys'] if st <= k[0] <= en]
    if not ks:
        # значение на момент начала из последнего ключа до интервала
        prev = [k for k in tr['keys'] if k[0] < st]
        if prev:
            ks = [[0.0, float(prev[-1][1][0])]]
    return {'keys': ks, 'step': tr['interp'] == 0}


def node_paths(M, oid, names):
    """Мировая позиция/поворот узла по каждой анимации (FPS кадров/с)."""
    out = {}
    for si, s in enumerate(M['sequences']):
        dur = max(1, s['end'] - s['start'])
        n = max(2, min(240, int(dur / 1000.0 * FPS) + 1))
        pos, rot = [], []
        for i in range(n):
            t = s['start'] + dur * i / (n - 1)
            W = pose.node_worlds(M, s, t)
            m = W.get(oid, np.eye(4))
            pos.append([round(x, 4) for x in conv(m[:3, 3])])
            rot.append(mat_to_quat(m[:3, :3]))
        # сжатие: неподвижный узел — один кадр
        if all(p == pos[0] for p in pos) and all(r == rot[0] for r in rot):
            pos, rot = pos[:1], rot[:1]
        out[names[si]] = {'pos': pos, 'rot': rot}
    return out


def save_tex(read_file, path, out_png, mode, max_px=256):
    data = read_file(path)
    if data is None or data[:4] == b'\x89PNG' and path.lower().endswith(('.blp', '.tga')):
        return False
    try:
        import blp
        im = blp.open_image(data)
    except Exception:
        return False
    im = im.convert('RGBA')
    if max(im.size) > max_px:
        k = max_px / max(im.size)
        im = im.resize((max(1, int(im.size[0] * k)), max(1, int(im.size[1] * k))), Image.LANCZOS)
    if mode == 'add':
        a = np.asarray(im).astype(np.float32)
        rgb = a[..., :3] * (a[..., 3:4] / 255.0)
        im = Image.fromarray(np.dstack([rgb, np.full(rgb.shape[:2], 255.0)]).astype(np.uint8), 'RGBA')
    im.save(out_png, 'PNG', optimize=True)
    return True


FILTER = {0: 'blend', 1: 'add', 2: 'mod', 3: 'mod2x', 4: 'alphakey'}


def convert_one(key, data, read_file, out_dir):
    M = mdx.parse(data)
    name = safe_name(key)
    names = anim_names(M)
    info = {'anims': {}, 'emitters': [], 'ribbons': [], 'glb': ''}
    for si, s in enumerate(M['sequences']):
        info['anims'][names[si]] = [round(max(1, s['end'] - s['start']) / 1000.0, 3), not s['nonloop']]
    # меши (если есть видимые части с текстурами)
    if M['geosets']:
        try:
            r = mdx2gltf.convert(M, read_file, os.path.join(out_dir, name + '.glb'), log=lambda *a: None, effect=True)
            if r.get('geosets'):
                info['glb'] = name + '.glb'
            else:
                os.remove(os.path.join(out_dir, name + '.glb'))
        except Exception as ex:  # noqa: BLE001
            info['glb_error'] = str(ex)[:200]
    # плавное появление/исчезание частей эффекта (KGAO у части, KMTA у слоя материала)
    ga_tr = {}
    for gi, g in enumerate(M['geosets']):
        tracks = []
        for a_ in M['geoanims']:
            if a_['geoset'] == gi and 'KGAO' in a_['tracks']:
                tracks.append(a_['tracks']['KGAO'])
        mat = M['materials'][g['material']] if g['material'] < len(M['materials']) else None
        if mat:
            for lay in mat['layers']:
                if 'KMTA' in lay['tracks']:
                    tracks.append(lay['tracks']['KMTA'])
                    break
        if not tracks:
            continue
        per = {}
        for si, sq in enumerate(M['sequences']):
            ks = [track_keys(M, t, sq) for t in tracks]
            ks = [k for k in ks if k]
            if ks:
                per[names[si]] = ks
        if per:
            ga_tr['Geo%d' % gi] = per
    if ga_tr:
        info['geo_alpha'] = ga_tr
    # частицы
    for oid, nd in sorted(M['nodes'].items()):
        if 'pe' in nd:
            e = nd['pe']
            tex = ''
            mode = FILTER.get(e['filter'], 'blend')
            if e['rid'] == 0 and e['tex'] < len(M['textures']):
                tp = M['textures'][e['tex']]['path']
                if M['textures'][e['tex']]['rid'] == 0 and tp:
                    fn = '%s_p%d.png' % (name, oid)
                    if save_tex(read_file, tp, os.path.join(out_dir, fn), mode):
                        tex = fn
            seqtr = {}
            for si, s in enumerate(M['sequences']):
                seqtr[names[si]] = {k: track_keys(M, e['tracks'].get(t), s)
                                    for k, t in (('rate', 'KP2E'), ('vis', 'KP2V'), ('speed', 'KP2S'),
                                                 ('width', 'KP2W'), ('length', 'KP2N'), ('lat', 'KP2L'),
                                                 ('grav', 'KP2G'), ('var', 'KP2R'))
                                    if e['tracks'].get(t) is not None}
            flags = nd['flags']
            info['emitters'].append({
                'node': oid, 'name': nd['name'], 'speed': e['speed'] * SCALE, 'variation': e['variation'],
                'latitude': e['latitude'], 'gravity': e['gravity'] * SCALE, 'lifespan': e['lifespan'],
                'rate': e['rate'], 'width': e['width'] * SCALE, 'length': e['length'] * SCALE,
                'filter': mode, 'rows': e['rows'], 'cols': e['cols'], 'head_tail': e['head_tail'],
                'tail_len': e['tail_len'], 'time': e['time'],
                'colors': [[c[2], c[1], c[0]] for c in e['colors']], 'alphas': e['alphas'],
                'scaling': [x * SCALE for x in e['scaling']], 'head': e['head'], 'head_decay': e['head_decay'],
                'tail': e['tail'], 'tail_decay': e['tail_decay'], 'squirt': e['squirt'], 'tex': tex,
                'unshaded': bool(flags & 0x8000), 'line': bool(flags & 0x20000), 'model_space': bool(flags & 0x80000),
                'xy_quad': bool(flags & 0x100000), 'tracks': seqtr, 'path': node_paths(M, oid, names)})
        if 'rb' in nd:
            e = nd['rb']
            tex = ''
            mat = M['materials'][e['material']] if e['material'] < len(M['materials']) else None
            mode = 'blend'
            if mat and mat['layers']:
                lay = mat['layers'][0]
                mode = {0: 'blend', 1: 'blend', 2: 'blend', 3: 'add', 4: 'add', 5: 'mod', 6: 'mod'}.get(lay['filter'], 'blend')
                if lay['tex'] < len(M['textures']) and M['textures'][lay['tex']]['path']:
                    fn = '%s_r%d.png' % (name, oid)
                    if save_tex(read_file, M['textures'][lay['tex']]['path'], os.path.join(out_dir, fn), mode):
                        tex = fn
            seqtr = {}
            for si, s in enumerate(M['sequences']):
                seqtr[names[si]] = {k: track_keys(M, e['tracks'].get(t), s)
                                    for k, t in (('vis', 'KRVS'), ('alpha', 'KRAL'), ('above', 'KRHA'), ('below', 'KRHB'))
                                    if e['tracks'].get(t) is not None}
            info['ribbons'].append({
                'node': oid, 'above': e['above'] * SCALE, 'below': e['below'] * SCALE, 'alpha': e['alpha'],
                'color': [e['color'][2], e['color'][1], e['color'][0]], 'lifespan': e['lifespan'], 'rate': e['rate'],
                'rows': e['rows'], 'cols': e['cols'], 'gravity': e['gravity'] * SCALE, 'filter': mode, 'tex': tex,
                'tracks': seqtr, 'path': node_paths(M, oid, names)})
    if not info['glb'] and not info['emitters'] and not info['ribbons']:
        info['empty'] = True
    json.dump(info, open(os.path.join(out_dir, name + '.fx.json'), 'w'), separators=(',', ':'))
    return name, info


def main():
    need = json.load(open(sys.argv[1]))
    out_dir = sys.argv[2]
    base_dir = sys.argv[3] if len(sys.argv) > 3 else None
    os.makedirs(out_dir, exist_ok=True)
    from mpq import MPQ
    mp = MPQ('/home/claude/work/map/Anime_Team_Survival_4_9v.w3x')
    cache = {}

    def read_file(path):
        k = path.lower().replace('/', '\\')
        if k in cache:
            return cache[k]
        d = mp.read(path) if mp.has(path) else None
        if d is None and base_dir:
            p = os.path.join(base_dir, *k.split('\\'))
            for cand in (p, p.lower()):
                if os.path.isfile(cand):
                    d = open(cand, 'rb').read()
                    break
        cache[k] = d
        return d

    # стандартные текстуры Warcraft, которых нет в карте: мягкое пятно вместо них (до извлечения из игры)
    buf = io.BytesIO()
    g = Image.new('RGBA', (64, 64))
    for y in range(64):
        for x in range(64):
            d = ((x - 31.5) ** 2 + (y - 31.5) ** 2) ** 0.5 / 31.5
            a = max(0.0, 1.0 - d) ** 1.6
            g.putpixel((x, y), (46, 44, 52, int(a * 255)))
    g.save(buf, 'PNG')
    soft = buf.getvalue()
    mdx2gltf.SUBST_BYTES = soft
    substituted = set()
    plain_read = read_file

    def read_file_fx(path):
        d = plain_read(path)
        if d is None and path.lower().endswith(('.blp', '.tga')):
            substituted.add(path.lower())
            return soft
        return d

    index = {}
    items = list(need.get('map', {}).items())
    if base_dir:
        for k in need.get('base', []):
            items.append((k, k.replace('/', '\\') + '.mdx'))
    bad = []
    subst = {}
    for key, path in items:
        data = read_file(path)
        if data is None and path.endswith('.mdx'):
            data = read_file(path[:-4] + '.mdl')
        if data is None or data[:4] != b'MDLX':
            bad.append(key)
            continue
        try:
            substituted.clear()
            name, info = convert_one(key, data, read_file_fx, out_dir)
            index[key] = name
            if substituted:
                subst[key] = sorted(substituted)
        except Exception as ex:  # noqa: BLE001
            bad.append('%s: %s' % (key, ex))
    old = {}
    ip = os.path.join(out_dir, 'index.json')
    if os.path.isfile(ip):
        old = json.load(open(ip))
    old.update(index)
    json.dump(old, open(ip, 'w'), indent=0, sort_keys=True)
    json.dump(subst, open(os.path.join(out_dir, 'substituted.json'), 'w'), indent=0)
    print('converted', len(index), 'failed', len(bad), 'with substituted textures', len(subst))
    for b in bad[:30]:
        print('  ', b)


if __name__ == '__main__':
    main()

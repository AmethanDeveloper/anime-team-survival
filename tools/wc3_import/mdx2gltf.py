"""MDX (Warcraft III) -> GLB: геометрия, скелет, анимации, текстуры, видимость частей по анимациям."""
import io
import json
import re
import struct
import sys

from PIL import Image

import mdx

SCALE = 0.01  # единицы WC3 -> метры (герой ~1.5–2.5 м)
SUBST_BYTES = None  # байты текстуры-заглушки (эффекты без стандартных текстур Warcraft)


def conv(v):
    """WC3 (Z вверх, X вперёд) -> glTF (Y вверх, Z вперёд)."""
    return [v[1], v[2], v[0]]


def convq(q):
    return [q[1], q[2], q[0], q[3]]


def clean_name(s):
    s = re.sub(r'[^\x20-\x7e]', '', s).strip()
    return s or 'seq'


class Glb:
    def __init__(self):
        self.bin = bytearray()
        self.g = {'asset': {'version': '2.0', 'generator': 'ATS wc3 import'}, 'scene': 0, 'scenes': [{'nodes': []}],
                  'nodes': [], 'meshes': [], 'materials': [], 'textures': [], 'images': [], 'samplers': [],
                  'accessors': [], 'bufferViews': [], 'buffers': [], 'skins': [], 'animations': []}

    def view(self, data, target=None):
        while len(self.bin) % 4:
            self.bin.append(0)
        off = len(self.bin)
        self.bin += data
        v = {'buffer': 0, 'byteOffset': off, 'byteLength': len(data)}
        if target:
            v['target'] = target
        self.g['bufferViews'].append(v)
        return len(self.g['bufferViews']) - 1

    def acc(self, fmt, ctype, typ, rows, target=None, minmax=False, normalized=False):
        flat = [x for r in rows for x in (r if isinstance(r, (list, tuple)) else [r])]
        data = struct.pack('<%d%s' % (len(flat), fmt), *flat)
        v = self.view(data, target)
        a = {'bufferView': v, 'componentType': ctype, 'count': len(rows), 'type': typ}
        if normalized:
            a['normalized'] = True
        if minmax:
            n = len(rows[0]) if isinstance(rows[0], (list, tuple)) else 1
            if n == 1:
                a['min'] = [min(rows)]
                a['max'] = [max(rows)]
            else:
                a['min'] = [min(r[i] for r in rows) for i in range(n)]
                a['max'] = [max(r[i] for r in rows) for i in range(n)]
        self.g['accessors'].append(a)
        return len(self.g['accessors']) - 1

    def save(self, path):
        g = {k: v for k, v in self.g.items() if v != []}
        g['buffers'] = [{'byteLength': len(self.bin)}]
        js = json.dumps(g, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
        while len(js) % 4:
            js += b' '
        while len(self.bin) % 4:
            self.bin.append(0)
        total = 12 + 8 + len(js) + 8 + len(self.bin)
        with open(path, 'wb') as f:
            f.write(struct.pack('<III', 0x46546C67, 2, total))
            f.write(struct.pack('<II', len(js), 0x4E4F534A))
            f.write(js)
            f.write(struct.pack('<II', len(self.bin), 0x004E4942))
            f.write(self.bin)


def geo_alpha(model, gi, seq):
    """Видимость части модели в анимации: (видна ли вообще, ключи [(t, 0/1)])"""
    ga = None
    for a in model['geoanims']:
        if a['geoset'] == gi:
            ga = a
    if ga is None:
        return True, []
    tr = ga['tracks'].get('KGAO')
    st, en = seq['start'], seq['end']
    if tr is None:
        return ga['alpha'] > 0.01, []
    if tr['gs'] is not None:
        # глобальная последовательность — берём «видна, если хоть раз видна»
        vis = any(k[1][0] > 0.01 for k in tr['keys'])
        return vis, []
    keys = [(k[0], 1 if k[1][0] > 0.01 else 0) for k in tr['keys'] if st <= k[0] <= en]
    if not keys:
        return ga['alpha'] > 0.01, []  # без ключей в интервале — статичная прозрачность
    vis = any(v for _, v in keys)
    return vis, keys


def pick_layer(model, mat, texok):
    """Слой материала для glTF: основной текстурный слой, слой цвета команды под ним — запекаем."""
    layers = mat['layers']
    team_under = False
    for i, l in enumerate(layers):
        t = model['textures'][l['tex']] if l['tex'] < len(model['textures']) else None
        if t is None:
            continue
        if t['rid'] == 1:
            team_under = True
            continue
        if t['rid'] == 2:
            continue
        if t['path'] and texok(t['path']):
            return l, team_under and i > 0
    return None, False


def convert(model_bytes, read_file, out_path, team_color=(0.55, 0.55, 0.6), max_tex=1024, log=print, effect=False):
    M = mdx.parse(model_bytes) if isinstance(model_bytes, (bytes, bytearray)) else model_bytes
    seqs = M['sequences']
    nodes = M['nodes']
    piv = M['pivots']

    # ---------- выбор частей модели
    def texok(p):
        return read_file(p) is not None

    stand = None
    for s in seqs:
        n = s['name'].lower().strip()
        if n.startswith('stand') and 'alternate' not in n and 'portrait' not in n:
            if stand is None or n == 'stand' or (stand['name'].lower().strip() != 'stand' and len(n) < len(stand['name'])):
                stand = s
    if stand is None and seqs:
        stand = seqs[0]

    keep = []
    for gi, g in enumerate(M['geosets']):
        mat = M['materials'][g['material']]
        layer, team = pick_layer(M, mat, texok)
        if layer is None:
            continue
        vis_any = False
        for s in seqs:
            v, _ = geo_alpha(M, gi, s)
            vis_any = vis_any or v
        if not vis_any:
            continue
        in_stand = geo_alpha(M, gi, stand)[0] if stand else True
        additive = layer['filter'] in (3, 4, 5, 6)
        subst = False
        if effect and SUBST_BYTES is not None:
            tp_ = M['textures'][layer['tex']]['path']
            if read_file(tp_) == SUBST_BYTES:
                additive = True  # подменённая текстура — только мягкое свечение
                subst = True
        keep.append({'gi': gi, 'layer': layer, 'team': team, 'stand': in_stand, 'additive': additive, 'subst': subst})

    # ---------- поза стойки: настоящий рост, центр тела, лишние ауры
    import numpy as np
    import pose
    W0 = pose.node_worlds(M, stand, stand['start']) if stand else {}
    posed = {k['gi']: pose.posed_vertices(M, k['gi'], W0) for k in keep}

    def is_effect(k):
        tex = M['textures'][k['layer']['tex']]['path'].lower()
        return k['additive'] or 'spell' in tex or 'glow' in tex

    def nverts(k):
        return len(M['geosets'][k['gi']]['verts']) // 3

    core = [k for k in keep if k['stand'] and not is_effect(k) and nverts(k) >= 30]
    if not core:
        core = [k for k in keep if k['stand']] or keep
    if effect or not core:
        core = keep
    C = np.vstack([posed[k['gi']] for k in core]) if core else np.zeros((1, 3))
    cx, cy = float(np.median(C[:, 0])), float(np.median(C[:, 1]))
    rad = float(np.percentile(np.hypot(C[:, 0] - cx, C[:, 1] - cy), 98))
    dropped = []
    for k in ([] if effect else list(keep)):
        if k['stand'] and is_effect(k):
            P = posed[k['gi']]
            if np.hypot(P[:, 0] - cx, P[:, 1] - cy).max() > max(1.5 * rad, 120.0):
                keep.remove(k)
                dropped.append(k['gi'])
    body_h = float(C[:, 2].max()) * SCALE
    body_floor = float(C[:, 2].min()) * SCALE
    core_ids = {k['gi']: nverts(k) for k in core}

    def vis_at(gi, s, t):
        v, keys = geo_alpha(M, gi, s)
        if not keys:
            return v
        cur = keys[0][1]
        for kt, kv in keys:
            if kt <= t:
                cur = kv
        return bool(cur)

    body_vis = {}
    for s in seqs:
        times = {s['start']}
        for gi in core_ids:
            for kt, _ in geo_alpha(M, gi, s)[1]:
                times.add(kt)
        tot = float(sum(core_ids.values())) or 1.0
        worst = 1.0
        for t in sorted(times):
            f = sum(n for gi, n in core_ids.items() if vis_at(gi, s, t)) / tot
            worst = min(worst, f)
        body_vis[s['name']] = worst

    # ---------- узлы: все объекты модели становятся костями одного скелета
    ids = sorted(nodes)
    jidx = {}
    G = Glb()
    root = 0
    G.g['nodes'].append({'name': 'Model', 'children': []})
    for oid in ids:
        jidx[oid] = len(G.g['nodes'])
        nd = nodes[oid]
        G.g['nodes'].append({'name': ('n%d' % oid) if effect else (clean_name(nd['name']) or 'node%d' % oid)})

    def pv(oid):
        return piv[oid] if oid < len(piv) else [0.0, 0.0, 0.0]

    def rest_t(oid):
        p = pv(oid)
        par = nodes[oid]['parent']
        pp = pv(par) if par is not None and par in nodes else [0.0, 0.0, 0.0]
        return [(a - b) for a, b in zip(p, pp)]

    for oid in ids:
        nd = nodes[oid]
        gl = G.g['nodes'][jidx[oid]]
        t = conv(rest_t(oid))
        gl['translation'] = [x * SCALE for x in t]
        par = nd['parent']
        if par is not None and par in nodes:
            G.g['nodes'][jidx[par]].setdefault('children', []).append(jidx[oid])
        else:
            G.g['nodes'][root]['children'].append(jidx[oid])

    joints = [jidx[o] for o in ids]
    ibm = []
    for oid in ids:
        p = conv(pv(oid))
        ibm.append([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -p[0] * SCALE, -p[1] * SCALE, -p[2] * SCALE, 1])
    G.g['skins'].append({'joints': joints, 'inverseBindMatrices': G.acc('f', 5126, 'MAT4', ibm), 'skeleton': root})
    jpos = {oid: i for i, oid in enumerate(ids)}

    # ---------- текстуры и материалы
    img_cache = {}

    def image_index(path, team, additive, alpha_used):
        key = (path.lower(), team, additive)
        if key in img_cache:
            return img_cache[key]
        import blp
        im = blp.open_image(read_file(path))
        im = im.convert('RGBA')
        if max(im.size) > max_tex:
            k = max_tex / max(im.size)
            im = im.resize((max(1, int(im.size[0] * k)), max(1, int(im.size[1] * k))), Image.LANCZOS)
        if team:
            bg = Image.new('RGBA', im.size, tuple(int(c * 255) for c in team_color) + (255,))
            im = Image.alpha_composite(bg, im)
        if additive:
            # аддитивная текстура: прозрачность из яркости, чтобы чёрный фон исчез
            import numpy as np
            a = np.asarray(im).astype(np.float32)
            mx = a[..., :3].max(axis=2)
            safe = np.maximum(mx, 1.0)
            rgb = np.clip(a[..., :3] * (255.0 / safe[..., None]), 0, 255)
            alpha = mx * a[..., 3] / 255.0
            im = Image.fromarray(np.dstack([rgb, alpha]).astype(np.uint8), 'RGBA')
        buf = io.BytesIO()
        im.save(buf, 'PNG', optimize=True)
        v = G.view(bytes(buf.getvalue()))
        G.g['images'].append({'bufferView': v, 'mimeType': 'image/png', 'name': re.sub(r'[\\/]', '_', path)})
        G.g['textures'].append({'source': len(G.g['images']) - 1, 'sampler': 0})
        img_cache[key] = len(G.g['textures']) - 1
        return img_cache[key]

    G.g['samplers'].append({'magFilter': 9729, 'minFilter': 9987, 'wrapS': 10497, 'wrapT': 10497})
    mat_cache = {}
    used_ext = set()

    def geo_tint(gi):
        """Статичный цвет и прозрачность части эффекта (geoset animation): ([r,g,b], alpha)."""
        ga = None
        for a_ in M['geoanims']:
            if a_['geoset'] == gi:
                ga = a_
        if ga is None:
            return [1.0, 1.0, 1.0], 1.0
        col = [ga['color'][2], ga['color'][1], ga['color'][0]] if ga['flags'] & 2 else [1.0, 1.0, 1.0]
        tc = ga['tracks'].get('KGAC')
        if tc is not None and tc['keys'] and ga['flags'] & 2:
            v = tc['keys'][0][1]
            col = [v[2], v[1], v[0]]
        al = 1.0 if 'KGAO' in ga['tracks'] else max(0.0, min(1.0, ga['alpha']))
        return [max(0.0, min(1.0, c)) for c in col], al

    def material_index(k):
        l = k['layer']
        key = (id(l), k['team'], k['gi'] if effect else 0)
        if key in mat_cache:
            return mat_cache[key]
        tpath = M['textures'][l['tex']]['path']
        ti = image_index(tpath, k['team'], k['additive'], l['filter'] in (1, 2))
        bl = ('@add' if k.get('subst') or (k['additive'] and l['filter'] not in (5, 6)) else
              {2: '@blend', 3: '@add', 4: '@add', 5: '@mod', 6: '@mod'}.get(l['filter'], '')) if effect else ''
        m = {'name': tpath.split('\\')[-1].rsplit('.', 1)[0] + bl,
             'pbrMetallicRoughness': {'baseColorTexture': {'index': ti}, 'metallicFactor': 0.0, 'roughnessFactor': 0.9}}
        f = l['filter']
        if k['team'] or f == 0:
            m['alphaMode'] = 'OPAQUE'
        elif f == 1:
            m['alphaMode'] = 'MASK'
            m['alphaCutoff'] = 0.5
        else:
            m['alphaMode'] = 'BLEND'
        if l['shading'] & 0x10:
            m['doubleSided'] = True
        if effect:
            col, al = geo_tint(k['gi'])
            if 'KMTA' not in l['tracks']:
                al *= max(0.0, min(1.0, l.get('alpha', 1.0)))
            if col != [1.0, 1.0, 1.0] or al < 0.999:
                m['pbrMetallicRoughness']['baseColorFactor'] = col + [al]
                if al < 0.999 and m.get('alphaMode', 'OPAQUE') == 'OPAQUE':
                    m['alphaMode'] = 'BLEND'
        if l['shading'] & 0x1 or k['additive']:
            m['extensions'] = {'KHR_materials_unlit': {}}
            used_ext.add('KHR_materials_unlit')
        G.g['materials'].append(m)
        mat_cache[key] = len(G.g['materials']) - 1
        return mat_cache[key]

    # ---------- сетки
    mesh_nodes = {}
    bmin = [1e9] * 3
    bmax = [-1e9] * 3
    for k in keep:
        g = M['geosets'][k['gi']]
        nv = len(g['verts']) // 3
        pos = [[x * SCALE for x in conv(g['verts'][i * 3:i * 3 + 3])] for i in range(nv)]
        nrm = []
        for i in range(nv):
            n = conv(g['normals'][i * 3:i * 3 + 3]) if len(g['normals']) >= i * 3 + 3 else [0, 1, 0]
            l = sum(x * x for x in n) ** 0.5 or 1.0
            nrm.append([x / l for x in n])
        uv = [g['uvs'][0][i * 2:i * 2 + 2] for i in range(nv)] if g['uvs'] else [[0.0, 0.0]] * nv
        # группы костей
        offs = []
        o = 0
        for c in g['mtgc']:
            offs.append(o)
            o += c
        J = []
        W = []
        for i in range(nv):
            gi = g['vgroups'][i] if i < len(g['vgroups']) else 0
            if gi >= len(offs):
                gi = 0
            bones = g['mats'][offs[gi]:offs[gi] + g['mtgc'][gi]] if g['mtgc'] else []
            bones = [b for b in bones if b in jpos][:4]
            if not bones:
                bones = [ids[0]]
            w = 1.0 / len(bones)
            J.append([jpos[b] for b in bones] + [0] * (4 - len(bones)))
            W.append([w] * len(bones) + [0.0] * (4 - len(bones)))
        idx = []
        p = 0
        for t, c in zip(g['ptypes'], g['pcounts']):
            if t == 4:
                idx += g['faces'][p:p + c]
            p += c
        if not idx:
            continue
        if k['stand']:
            for v in pos:
                for a in range(3):
                    bmin[a] = min(bmin[a], v[a])
                    bmax[a] = max(bmax[a], v[a])
        attrs = {
            'POSITION': G.acc('f', 5126, 'VEC3', pos, 34962, minmax=True),
            'NORMAL': G.acc('f', 5126, 'VEC3', nrm, 34962),
            'TEXCOORD_0': G.acc('f', 5126, 'VEC2', uv, 34962),
            'JOINTS_0': G.acc('H', 5123, 'VEC4', J, 34962),
            'WEIGHTS_0': G.acc('f', 5126, 'VEC4', W, 34962),
        }
        ind = G.acc('I' if nv > 65535 else 'H', 5125 if nv > 65535 else 5123, 'SCALAR', idx, 34963)
        prim = {'attributes': attrs, 'indices': ind, 'material': material_index(k)}
        G.g['meshes'].append({'name': 'geo%d' % k['gi'], 'primitives': [prim]})
        ni = len(G.g['nodes'])
        G.g['nodes'].append({'name': 'Geo%d' % k['gi'], 'mesh': len(G.g['meshes']) - 1, 'skin': 0})
        G.g['scenes'][0]['nodes'].append(ni)
        mesh_nodes[k['gi']] = ni
    G.g['scenes'][0]['nodes'].insert(0, root)

    # ---------- анимации
    names_used = {}
    anim_names = []
    for s in seqs:
        nm = clean_name(s['name'])
        base = nm
        c = names_used.get(base.lower(), 0)
        names_used[base.lower()] = c + 1
        if c:
            nm = '%s %d' % (base, c + 1)
        anim_names.append(nm)
        st, en = s['start'], s['end']
        dur = max(1, en - st)
        samplers = []
        channels = []

        def add(node_i, path, times, vals, typ, interp='LINEAR'):
            ti = G.acc('f', 5126, 'SCALAR', times, minmax=True)
            vi = G.acc('f', 5126, typ, vals)
            samplers.append({'input': ti, 'output': vi, 'interpolation': interp})
            channels.append({'sampler': len(samplers) - 1, 'target': {'node': node_i, 'path': path}})

        for oid in ids:
            nd = nodes[oid]
            for tag, path, default, quat in (('KGTR', 'translation', [0, 0, 0], False),
                                              ('KGRT', 'rotation', [0, 0, 0, 1], True),
                                              ('KGSC', 'scale', [1, 1, 1], False)):
                tr = nd['tracks'].get(tag)
                if tr is None or not tr['keys']:
                    continue
                if tr['gs'] is not None and tr['gs'] < len(M['globalseqs']):
                    gd = M['globalseqs'][tr['gs']] or 1
                    step = 50
                    tl = list(range(0, dur + 1, step))
                    if tl[-1] != dur:
                        tl.append(dur)
                    vals = [mdx.eval_keys(tr, t % gd, 0, gd, default, quat) for t in tl]
                else:
                    kt = sorted(set([st, en] + [k[0] for k in tr['keys'] if st <= k[0] <= en]))
                    if tr['interp'] >= 2 and not quat:
                        extra = []
                        for a, b in zip(kt, kt[1:]):
                            n = min(4, (b - a) // 40)
                            extra += [a + (b - a) * i // (n + 1) for i in range(1, n + 1)]
                        kt = sorted(set(kt + extra))
                    vals = [mdx.eval_keys(tr, t, st, en, default, quat) for t in kt]
                    tl = [t - st for t in kt]
                if path == 'translation':
                    rt = rest_t(oid)
                    out = [[x * SCALE for x in conv([a + b for a, b in zip(v, rt)])] for v in vals]
                    typ = 'VEC3'
                elif path == 'rotation':
                    out = [mdx._qnorm(convq(v)) for v in vals]
                    typ = 'VEC4'
                else:
                    out = [conv(v) for v in vals]
                    typ = 'VEC3'
                if all(o == out[0] for o in out):
                    tl, out = [0.0], [out[0]]
                add(jidx[oid], path, [t / 1000.0 for t in tl], out, typ)
        # видимость частей
        for k in keep:
            if k['gi'] not in mesh_nodes:
                continue
            vis, keys = geo_alpha(M, k['gi'], s)
            if keys:
                tl = [0.0]
                vv = [keys[0][1]]
                for t, v in keys:
                    tl.append((t - st) / 1000.0)
                    vv.append(v)
                pairs = sorted(dict(zip(tl, vv)).items())
                tl = [p[0] for p in pairs]
                vv = [p[1] for p in pairs]
            else:
                tl, vv = [0.0], [1 if vis else 0]
            ti = G.acc('f', 5126, 'SCALAR', tl, minmax=True)
            vi = G.acc('B', 5121, 'SCALAR', vv)
            samplers.append({'input': ti, 'output': vi, 'interpolation': 'STEP'})
            channels.append({'sampler': len(samplers) - 1, 'target': {'path': 'pointer', 'extensions': {
                'KHR_animation_pointer': {'pointer': '/nodes/%d/extensions/KHR_node_visibility/visible' % mesh_nodes[k['gi']]}}}})
            used_ext.update(['KHR_animation_pointer', 'KHR_node_visibility'])
        if channels:
            G.g['animations'].append({'name': nm, 'samplers': samplers, 'channels': channels})

    for gi, ni in mesh_nodes.items():
        kk = [k for k in keep if k['gi'] == gi][0]
        G.g['nodes'][ni]['extensions'] = {'KHR_node_visibility': {'visible': bool(kk['stand'])}}
        used_ext.add('KHR_node_visibility')
    if used_ext:
        G.g['extensionsUsed'] = sorted(used_ext)
    G.save(out_path)
    vis_by_name = {anim_names[i]: body_vis.get(s['name'], 1.0) for i, s in enumerate(seqs)}
    return {'anims': anim_names, 'bounds': [bmin, bmax], 'geosets': len(keep), 'nodes': len(ids),
            'stand_geosets': sum(1 for k in keep if k['stand']), 'height': body_h, 'floor': body_floor,
            'body_vis': vis_by_name, 'dropped': dropped,
            'durations': {anim_names[i]: (s['end'] - s['start']) / 1000.0 for i, s in enumerate(seqs)}}


if __name__ == '__main__':
    pass

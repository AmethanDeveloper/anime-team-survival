"""Парсер моделей Warcraft III (MDX, версия 800)."""
import struct

NONE = 0xFFFFFFFF


class R:
    def __init__(self, b, p=0):
        self.b = b
        self.p = p

    def u32(self):
        v = struct.unpack_from('<I', self.b, self.p)[0]
        self.p += 4
        return v

    def i32(self):
        v = struct.unpack_from('<i', self.b, self.p)[0]
        self.p += 4
        return v

    def f32(self):
        v = struct.unpack_from('<f', self.b, self.p)[0]
        self.p += 4
        return v

    def fs(self, n):
        v = struct.unpack_from('<%df' % n, self.b, self.p)
        self.p += 4 * n
        return list(v)

    def tag(self):
        v = self.b[self.p:self.p + 4].decode('latin1')
        self.p += 4
        return v

    def peek(self):
        return self.b[self.p:self.p + 4].decode('latin1')

    def s(self, n):
        v = self.b[self.p:self.p + n].split(b'\0')[0].decode('latin1')
        self.p += n
        return v


TRACK_SIZES = {
    'KGTR': ('f', 3), 'KGRT': ('f', 4), 'KGSC': ('f', 3),
    'KMTF': ('u', 1), 'KMTA': ('f', 1), 'KGAO': ('f', 1), 'KGAC': ('f', 3), 'KATV': ('f', 1),
    'KLAV': ('f', 1), 'KTAT': ('f', 3), 'KTAR': ('f', 4), 'KTAS': ('f', 3),
    'KRCO': ('f', 3), 'KRTX': ('u', 1), 'KLAC': ('f', 3), 'KLBC': ('f', 3),
}


def read_track(r, tag):
    kind, n = TRACK_SIZES.get(tag, ('f', 1))
    count = r.u32()
    interp = r.u32()
    gs = r.u32()
    keys = []
    for _ in range(count):
        t = r.i32()
        if kind == 'u':
            v = [r.u32() for _ in range(n)]
        else:
            v = r.fs(n)
        if interp > 1:
            tin = r.fs(n) if kind == 'f' else [r.u32() for _ in range(n)]
            tout = r.fs(n) if kind == 'f' else [r.u32() for _ in range(n)]
        else:
            tin = tout = None
        keys.append((t, v, tin, tout))
    return {'interp': interp, 'gs': None if gs == NONE else gs, 'keys': keys}


def read_node(r):
    start = r.p
    size = r.u32()
    end = start + size
    node = {'name': r.s(80), 'id': r.u32(), 'parent': r.u32(), 'flags': r.u32(), 'tracks': {}}
    if node['parent'] == NONE:
        node['parent'] = None
    while r.p < end:
        tag = r.tag()
        node['tracks'][tag] = read_track(r, tag)
    r.p = end
    return node


def _read_tracks(r, end):
    tr = {}
    while r.p + 4 <= end:
        t = r.tag()
        if not t.startswith('K'):
            r.p -= 4
            break
        tr[t] = read_track(r, t)
    return tr


def _read_pre2(r, end):
    e = {}
    for k in ('speed', 'variation', 'latitude', 'gravity', 'lifespan', 'rate', 'width', 'length'):
        e[k] = r.f32()
    e['filter'] = r.u32()
    e['rows'], e['cols'] = r.u32(), r.u32()
    e['head_tail'] = r.u32()
    e['tail_len'], e['time'] = r.f32(), r.f32()
    e['colors'] = [r.fs(3) for _ in range(3)]
    e['alphas'] = list(r.b[r.p:r.p + 3])
    r.p += 3
    e['scaling'] = r.fs(3)
    e['head'] = [r.u32() for _ in range(3)]
    e['head_decay'] = [r.u32() for _ in range(3)]
    e['tail'] = [r.u32() for _ in range(3)]
    e['tail_decay'] = [r.u32() for _ in range(3)]
    e['tex'] = r.u32()
    e['squirt'] = r.u32()
    e['priority'] = r.i32()
    e['rid'] = r.u32()
    e['tracks'] = _read_tracks(r, end)
    return e


def _read_ribb(r, end):
    e = {}
    e['above'], e['below'], e['alpha'] = r.f32(), r.f32(), r.f32()
    e['color'] = r.fs(3)
    e['lifespan'] = r.f32()
    e['tex_slot'] = r.u32()
    e['rate'] = r.u32()
    e['rows'], e['cols'] = r.u32(), r.u32()
    e['material'] = r.u32()
    e['gravity'] = r.f32()
    e['tracks'] = _read_tracks(r, end)
    return e


def parse(data):
    if data[:4] != b'MDLX':
        raise ValueError('not MDX')
    r = R(data, 4)
    m = {'version': None, 'sequences': [], 'globalseqs': [], 'textures': [], 'materials': [], 'geosets': [],
         'geoanims': [], 'nodes': {}, 'pivots': [], 'bones': set(), 'kinds': {}}
    while r.p + 8 <= len(data):
        tag = r.tag()
        size = r.u32()
        cstart = r.p
        cend = cstart + size
        if tag == 'VERS':
            m['version'] = r.u32()
        elif tag == 'SEQS':
            while r.p < cend:
                name = r.s(80)
                st, en = r.u32(), r.u32()
                spd = r.f32()
                flags = r.u32()
                rar = r.f32()
                sync = r.u32()
                ext = r.fs(7)
                m['sequences'].append({'name': name, 'start': st, 'end': en, 'nonloop': flags & 1, 'extent': ext})
        elif tag == 'GLBS':
            m['globalseqs'] = [r.u32() for _ in range(size // 4)]
        elif tag == 'TEXS':
            while r.p < cend:
                rid = r.u32()
                path = r.s(260)
                fl = r.u32()
                m['textures'].append({'rid': rid, 'path': path, 'flags': fl})
        elif tag == 'MTLS':
            while r.p < cend:
                ms = r.p
                msize = r.u32()
                prio = r.i32()
                mflags = r.u32()
                layers = []
                if m['version'] and m['version'] > 800:
                    r.s(80)  # shader name (v900+)
                assert r.tag() == 'LAYS'
                nl = r.u32()
                for _ in range(nl):
                    ls = r.p
                    lsize = r.u32()
                    lay = {'filter': r.u32(), 'shading': r.u32(), 'tex': r.u32(), 'txanim': r.u32(),
                           'coord': r.u32(), 'alpha': r.f32(), 'tracks': {}}
                    if m['version'] and m['version'] > 800:
                        r.p = ls + lsize
                    while r.p < ls + lsize:
                        t = r.tag()
                        lay['tracks'][t] = read_track(r, t)
                    r.p = ls + lsize
                    layers.append(lay)
                m['materials'].append({'prio': prio, 'flags': mflags, 'layers': layers})
                r.p = ms + msize
        elif tag == 'GEOS':
            while r.p < cend:
                gs = r.p
                gsize = r.u32()
                g = {}
                assert r.tag() == 'VRTX'
                n = r.u32()
                g['verts'] = r.fs(3 * n)
                assert r.tag() == 'NRMS'
                n = r.u32()
                g['normals'] = r.fs(3 * n)
                assert r.tag() == 'PTYP'
                n = r.u32()
                g['ptypes'] = [r.u32() for _ in range(n)]
                assert r.tag() == 'PCNT'
                n = r.u32()
                g['pcounts'] = [r.u32() for _ in range(n)]
                assert r.tag() == 'PVTX'
                n = r.u32()
                g['faces'] = list(struct.unpack_from('<%dH' % n, data, r.p))
                r.p += 2 * n
                assert r.tag() == 'GNDX'
                n = r.u32()
                g['vgroups'] = list(data[r.p:r.p + n])
                r.p += n
                assert r.tag() == 'MTGC'
                n = r.u32()
                g['mtgc'] = [r.u32() for _ in range(n)]
                assert r.tag() == 'MATS'
                n = r.u32()
                g['mats'] = [r.u32() for _ in range(n)]
                g['material'] = r.u32()
                g['selgroup'] = r.u32()
                g['selflags'] = r.u32()
                g['extent'] = r.fs(7)
                ne = r.u32()
                r.p += 28 * ne
                g['uvs'] = []
                if r.peek() == 'UVAS':
                    r.tag()
                    nuv = r.u32()
                    for _ in range(nuv):
                        assert r.tag() == 'UVBS'
                        n = r.u32()
                        g['uvs'].append(r.fs(2 * n))
                r.p = gs + gsize
                m['geosets'].append(g)
        elif tag == 'GEOA':
            while r.p < cend:
                s0 = r.p
                sz = r.u32()
                ga = {'alpha': r.f32(), 'flags': r.u32(), 'color': r.fs(3), 'geoset': r.u32(), 'tracks': {}}
                while r.p < s0 + sz:
                    t = r.tag()
                    ga['tracks'][t] = read_track(r, t)
                r.p = s0 + sz
                m['geoanims'].append(ga)
        elif tag == 'BONE':
            while r.p < cend:
                nd = read_node(r)
                nd['geoset'] = r.u32()
                nd['geoanim'] = r.u32()
                m['nodes'][nd['id']] = nd
                m['kinds'][nd['id']] = 'bone'
                m['bones'].add(nd['id'])
        elif tag == 'HELP':
            while r.p < cend:
                nd = read_node(r)
                m['nodes'][nd['id']] = nd
                m['kinds'][nd['id']] = 'helper'
        elif tag == 'ATCH':
            while r.p < cend:
                s0 = r.p
                sz = r.u32()
                nd = read_node(r)
                nd['path'] = r.s(260)
                nd['attach_id'] = r.u32()
                r.p = s0 + sz
                m['nodes'][nd['id']] = nd
                m['kinds'][nd['id']] = 'attachment'
        elif tag == 'LITE':
            while r.p < cend:
                s0 = r.p
                sz = r.u32()
                nd = read_node(r)
                r.p = s0 + sz
                m['nodes'][nd['id']] = nd
                m['kinds'][nd['id']] = 'light'
        elif tag in ('PREM', 'PRE2', 'RIBB', 'EVTS', 'CLID', 'CORN'):
            # эмиттеры частиц, ленты, события, коллизии — тоже узлы иерархии
            while r.p < cend:
                s0 = r.p
                if tag in ('EVTS', 'CLID'):
                    nd = read_node(r)
                    if tag == 'EVTS':
                        if r.peek() == 'KEVT':
                            r.tag()
                            cnt = r.u32()
                            r.u32()
                            r.p += 4 * cnt
                    else:
                        shape = r.u32()
                        if shape == 0:
                            r.p += 24
                        elif shape == 1:
                            r.p += 12
                        elif shape == 2:
                            r.p += 16
                        else:
                            r.p += 28
                else:
                    sz = r.u32()
                    nd = read_node(r)
                    if tag == 'PRE2':
                        nd['pe'] = _read_pre2(r, s0 + sz)
                    elif tag == 'RIBB':
                        nd['rb'] = _read_ribb(r, s0 + sz)
                    r.p = s0 + sz
                m['nodes'][nd['id']] = nd
                m['kinds'][nd['id']] = tag.lower()
        elif tag == 'PIVT':
            for i in range(size // 12):
                m['pivots'].append(r.fs(3))
        r.p = cend
    return m


# ------------------------------------------------------------------ вычисление дорожек
def _lerp(a, b, t):
    return [x + (y - x) * t for x, y in zip(a, b)]


def _qnorm(q):
    l = sum(x * x for x in q) ** 0.5
    if not l or l != l:
        return [0.0, 0.0, 0.0, 1.0]
    return [x / l for x in q]


def _slerp(a, b, t):
    d = sum(x * y for x, y in zip(a, b))
    if d < 0:
        b = [-x for x in b]
        d = -d
    if d > 0.9995:
        return _qnorm(_lerp(a, b, t))
    import math
    th = math.acos(max(-1.0, min(1.0, d)))
    s = math.sin(th)
    wa = math.sin((1 - t) * th) / s
    wb = math.sin(t * th) / s
    return [x * wa + y * wb for x, y in zip(a, b)]


def _hermite(p0, o0, i1, p1, t):
    t2 = t * t
    t3 = t2 * t
    h1 = 2 * t3 - 3 * t2 + 1
    h2 = t3 - 2 * t2 + t
    h3 = t3 - t2
    h4 = -2 * t3 + 3 * t2
    return [a * h1 + b * h2 + c * h3 + d * h4 for a, b, c, d in zip(p0, o0, i1, p1)]


def _bezier(p0, o0, i1, p1, t):
    it = 1 - t
    f1 = it * it * it
    f2 = 3 * t * it * it
    f3 = 3 * t * t * it
    f4 = t * t * t
    return [a * f1 + b * f2 + c * f3 + d * f4 for a, b, c, d in zip(p0, o0, i1, p1)]


def eval_keys(track, t, start, end, default, quat=False):
    """Значение дорожки в момент t внутри интервала [start, end] (как в игре: ключи вне интервала не участвуют)."""
    keys = [k for k in track['keys'] if start <= k[0] <= end]
    if not keys:
        return list(default)
    if t <= keys[0][0]:
        return list(keys[0][1])
    if t >= keys[-1][0]:
        return list(keys[-1][1])
    for i in range(len(keys) - 1):
        a, b = keys[i], keys[i + 1]
        if a[0] <= t <= b[0]:
            if b[0] == a[0]:
                return list(b[1])
            f = (t - a[0]) / (b[0] - a[0])
            it = track['interp']
            if it == 0:
                return list(a[1])
            if quat:
                return _slerp(a[1], b[1], f)
            if it == 2 and a[3] is not None:
                return _hermite(a[1], a[3], b[2], b[1], f)
            if it == 3 and a[3] is not None:
                return _bezier(a[1], a[3], b[2], b[1], f)
            return _lerp(a[1], b[1], f)
    return list(keys[-1][1])

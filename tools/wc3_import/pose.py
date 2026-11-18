"""Поза модели в момент анимации: мировые матрицы узлов и скиннинг вершин (WC3-координаты)."""
import numpy as np
import mdx


def quat_mat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def node_worlds(M, seq, t):
    st, en = seq['start'], seq['end']
    nodes = M['nodes']
    piv = M['pivots']
    W = {}

    def world(oid):
        if oid in W:
            return W[oid]
        nd = nodes[oid]
        p = np.array(piv[oid] if oid < len(piv) else [0, 0, 0], dtype=float)

        def val(tag, default, quat=False):
            tr = nd['tracks'].get(tag)
            if tr is None:
                return default
            if tr['gs'] is not None:
                gd = M['globalseqs'][tr['gs']] if tr['gs'] < len(M['globalseqs']) else 0
                return mdx.eval_keys(tr, 0, 0, gd, default, quat)
            return mdx.eval_keys(tr, t, st, en, default, quat)

        T = np.array(val('KGTR', [0, 0, 0]), dtype=float)
        q = mdx._qnorm(val('KGRT', [0, 0, 0, 1], True))
        S = np.array(val('KGSC', [1, 1, 1]), dtype=float)
        L = np.eye(4)
        L[:3, :3] = quat_mat(q) @ np.diag(S)
        L[:3, 3] = p + T - L[:3, :3] @ p
        par = nd['parent']
        Wm = world(par) @ L if par is not None and par in nodes else L
        W[oid] = Wm
        return Wm

    for oid in nodes:
        world(oid)
    return W


def posed_vertices(M, gi, W):
    g = M['geosets'][gi]
    V = np.array(g['verts'], dtype=float).reshape(-1, 3)
    offs = np.cumsum([0] + g['mtgc'])
    out = np.zeros_like(V)
    Vh = np.c_[V, np.ones(len(V))]
    for i in range(len(V)):
        gi_ = g['vgroups'][i] if i < len(g['vgroups']) else 0
        if gi_ >= len(g['mtgc']):
            gi_ = 0
        bones = [b for b in g['mats'][offs[gi_]:offs[gi_ + 1]] if b in W]
        if not bones:
            out[i] = V[i]
            continue
        acc = np.zeros(4)
        for b in bones:
            acc += W[b] @ Vh[i]
        out[i] = (acc / len(bones))[:3]
    return out

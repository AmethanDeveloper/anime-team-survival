# -*- coding: utf-8 -*-
"""Какие триггеры карты относятся к героям: способности, врождённые навыки, сеты."""
import json
import pickle
import re
import sys
from collections import defaultdict

import jparse

HERE = '/home/claude/work/scripts/jass/'
ast = pickle.load(open(HERE + 'ast.pkl', 'rb'))
FUNCS = {f['name']: f for f in ast['functions']}
heroes = json.load(open('/home/claude/work/out/heroes_map.json'))

ID2HERO = {}
for h in heroes:
    ID2HERO[h['unit']] = h['id']
    for a in h['abilities'] + (h['innate'] or []) + (h['set_abilities'] or []):
        if a:
            ID2HERO.setdefault(a['id'], h['id'])
    if h.get('set_item'):
        ID2HERO[h['set_item']] = h['id']

PREFIX = {'Asuna': 'asuna', 'Archer': 'archer', 'Akame': 'akame', 'Est': 'est', 'BRS': 'brs', 'Black': 'brs',
          'Erza': 'erza', 'Esdeath': 'esdeath', 'Ichigo': 'ichigo', 'Ichgo': 'ichigo', 'Inori': 'inori',
          'Kotori': 'kotori', 'Kirito': 'kirito', 'Kurumi': 'kurumi', 'Misaka': 'misaka', 'Miku': 'miku',
          'Miyuki': 'miyuki', 'Natsu': 'natsu', 'Nastu': 'natsu', 'Saber': 'saber', 'Sephirot': 'sephiroth',
          'Shana': 'shana', 'Shiki': 'shiki', 'Shinobu': 'shinobu', 'Ray': 'shinobu', 'Kiss': 'shinobu',
          'KissShot': 'shinobu', 'Shiro': 'shiro', 'Sinon': 'sinon', 'Tama': 'tamamo', 'Tina': 'tina',
          'Tohka': 'tohka', 'Torka': 'tohka', 'Tsurara': 'tsurara', 'WRS': 'wrs', 'White': 'wrs', 'Yaya': 'yaya',
          'Yoshino': 'yoshino', 'Yuu': 'yuu', 'Origami': 'origami', 'Tobiichi': 'origami'}


def trig_funcs(tname):
    """Функции карты, достижимые из InitTrig_<tname>."""
    seen = set()
    stack = ['InitTrig_' + tname]
    while stack:
        n = stack.pop()
        if n in seen or n not in FUNCS:
            continue
        seen.add(n)
        for c in jparse.walk_calls(FUNCS[n]['body'], set()):
            if c in FUNCS and c not in seen:
                stack.append(c)
    return seen


def consts(fnames):
    out = set()

    def ex(e):
        if not isinstance(e, tuple):
            return
        if e and e[0] == 'int' and len(e) == 3:
            out.add(e[2])
        for x in e[1:]:
            if isinstance(x, tuple):
                ex(x)
            elif isinstance(x, list):
                for y in x:
                    if isinstance(y, tuple):
                        ex(y)
                    elif isinstance(y, list):
                        for z in y:
                            ex(z)

    for n in fnames:
        for s in FUNCS[n]['body']:
            ex(s)
    return out


def main():
    trigs = [f['name'][9:] for f in ast['functions'] if f['name'].startswith('InitTrig_')]
    owner = {}
    info = {}
    for t in trigs:
        fs = trig_funcs(t)
        cs = consts(fs)
        vs = set()
        for n in fs:
            jparse.walk_vars(FUNCS[n]['body'], vs)
        info[t] = (fs, cs, vs)
        hs = defaultdict(int)
        p = t.split('_')[0]
        if t.startswith('Hero_') or t.startswith('Boss') or t.startswith('Ultimate_Set_'):
            pass
        for c in cs:
            if c in ID2HERO:
                hs[ID2HERO[c]] += 1
        if p in PREFIX and not t.startswith('Hero_'):
            hs[PREFIX[p]] += 5
        if hs and not t.startswith('Hero_') and not t.startswith('Boss'):
            owner[t] = max(hs, key=hs.get)
    # замыкание: триггеры, которые включают/выключают/запускают триггеры героя
    changed = True
    while changed:
        changed = False
        for t, (fs, cs, vs) in info.items():
            if t in owner:
                for v in vs:
                    if v.startswith('gg_trg_'):
                        o = v[7:]
                        if o in info and o not in owner and not o.startswith('Hero_') and not o.startswith('Boss'):
                            owner[o] = owner[t]
                            changed = True
    byhero = defaultdict(list)
    for t in trigs:
        if t in owner:
            byhero[owner[t]].append(t)
    json.dump({h: v for h, v in byhero.items()}, open(HERE + 'scope.json', 'w'), indent=1)
    allf = set()
    for t in owner:
        allf |= info[t][0]
    calls = set()
    for n in allf:
        jparse.walk_calls(FUNCS[n]['body'], calls)
    natives = sorted(c for c in calls if c not in FUNCS)
    usedmap = sorted(c for c in calls if c in FUNCS and not c.startswith('Trig_') and not c.startswith('InitTrig_'))
    print('triggers', len(owner), 'functions', len(allf), 'lines~', sum(len(FUNCS[n]['body']) for n in allf))
    print('natives', len(natives))
    print(' '.join(natives))
    print('map helpers', usedmap)
    for h in sorted(byhero):
        print(h, len(byhero[h]))
    pickle.dump({'owner': owner, 'funcs': sorted(allf), 'natives': natives}, open(HERE + 'scope.pkl', 'wb'))


if __name__ == '__main__':
    main()

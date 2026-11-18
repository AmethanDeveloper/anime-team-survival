# -*- coding: utf-8 -*-
"""Данные карты для среды исполнения W3: способности, типы юнитов, модели, звуки -> w3_data.json.

Запуск: python export_w3.py <папка_вывода>
Также копирует звуки карты в <вывод>/sounds и пишет список моделей для конвертера (models_needed.json).
"""
import json
import os
import re
import sys

sys.path.insert(0, '/home/claude/work/scripts')
sys.path.insert(0, '/home/claude/work/scripts/jass')
from w3data import parse_slk, parse_profile  # noqa: E402
from w3obj import parse_obj  # noqa: E402
from mpq import MPQ  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else '/home/claude/work/scripts/jass/out/'
U = '/home/claude/work/ext/Units/'
B = '/home/claude/work/ext/base/Units/'
MAP = '/home/claude/work/map/Anime_Team_Survival_4_9v.w3x'

AD = parse_slk(U + 'AbilityData.slk')
PROF = parse_profile(U + 'CampaignAbilityStrings.txt')
META = parse_slk(B + 'AbilityMetaData.slk')
_, W3A = parse_obj('/home/claude/work/ext/war3map.w3a')
UI = parse_slk(U + 'UnitUI.slk')
UD = parse_slk(U + 'UnitData.slk')
UB = parse_slk(U + 'UnitBalance.slk')
UW = parse_slk(U + 'UnitWeapons.slk')
UA = parse_slk(U + 'UnitAbilities.slk')
UPROF = parse_profile(U + 'CampaignUnitFunc.txt')
HEROES = json.load(open('/home/claude/work/out/heroes_map.json'))
GD = open(OUT + 'w3_map.gd', encoding='utf-8').read()


def num(v, d=0.0):
    try:
        return float(v)
    except (TypeError, ValueError):
        return d


def fcc_str(n):
    return ''.join(chr((n >> s) & 255) for s in (24, 16, 8, 0))


# ---------------------------------------------------------------- ссылки в переведённом коде
ints = {int(x) for x in re.findall(r'(?<![\w.])(\d{9,10})(?![\w.])', GD)}
FCC = {fcc_str(i) for i in ints if 0x20202020 <= i <= 0x7a7a7a7a}
STRS = set(re.findall(r'"((?:[^"\\]|\\.)*)"', GD))


def art_fields(aid):
    p = dict(PROF.get(aid, {}))
    mods = W3A.get(aid, {}).get('mods', {})
    for (mid, lvl), v in mods.items():
        m = META.get(mid)
        if m and m.get('slk') == 'Profile' and isinstance(v, (str, int, float)):
            p[m['field']] = v
    norm = {}
    for k, v in p.items():
        norm[k.lower()] = v
    return norm


FIELD_KEYS = {'dataa': 'a', 'datab': 'b', 'datac': 'c', 'datad': 'd', 'datae': 'e', 'dataf': 'f', 'datag': 'g',
              'datah': 'h', 'datai': 'i', 'dur': 'dur', 'herodur': 'hdur', 'area': 'area', 'rng': 'rng', 'cool': 'cool',
              'cost': 'cost', 'cast': 'cast', 'targs': 'targs', 'buffid': 'buff', 'efctid': 'efct', 'unitid': 'unit'}


def ability(aid):
    r = AD.get(aid)
    if r is None:
        return None
    code = r.get('code', aid)
    lv = int(num(r.get('levels'), 1)) or 1
    levels = []
    for L in range(1, min(lv, 4) + 1):
        d = {}
        for k, v in r.items():
            m = re.match(r'^([A-Za-z]+?)(\d+)$', k)
            if not m or int(m.group(2)) != L:
                continue
            key = FIELD_KEYS.get(m.group(1).lower())
            if key is None:
                continue
            if key in ('targs', 'buff', 'efct', 'unit'):
                d[key] = v
            else:
                d[key] = num(v)
        levels.append(d)
    art = art_fields(aid)

    def g(k, d=''):
        v = art.get(k, d)
        return v if v is not None else d

    def first(v):
        return str(v).split(',')[0].strip() if v else ''
    return {
        'code': code, 'levels': levels, 'name': g('name'), 'hotkey': g('hotkey'), 'order': g('order'),
        'tip': re.sub(r'\|c[0-9a-fA-F]{8}|\|r|\(\|cff[0-9a-fA-F]{6}\w\|r\)', '', str(g('tip')).split(',')[0]).strip(),
        'ubertip': str(g('ubertip')),
        'art': {'missile': first(g('missileart')), 'missile_speed': num(g('missilespeed'), 900),
                'missile_arc': num(g('missilearc'), 0), 'effect': first(g('effectart')),
                'target': first(g('targetart')), 'target_attach': first(g('targetattach')) or 'origin',
                'caster': first(g('casterart')), 'caster_attach': first(g('casterattach')) or 'origin',
                'special': first(g('specialart')), 'special_attach': first(g('specialattach')) or 'origin',
                'area': first(g('areaeffectart')), 'lightning': first(g('lightningeffect')),
                'anim': str(g('animnames')), 'icon': first(g('art'))},
        'hero': aid in HERO_AB,
    }


HERO_AB = set()
for h in HEROES:
    for a in h['abilities'] + (h['innate'] or []) + (h['set_abilities'] or []):
        if a:
            HERO_AB.add(a['id'])


def unit(uid):
    ui, ud, ub, uw, ua, up = (t.get(uid, {}) for t in (UI, UD, UB, UW, UA, UPROF))
    if not ui and not ub:
        return None
    abl = [x for x in (ua.get('abilList', '') or '').split(',') if x and x != '_']
    habl = [x for x in (ua.get('heroAbilList', '') or '').split(',') if x and x != '_']
    dice, sides, plus = num(uw.get('dice1'), 0), num(uw.get('sides1'), 0), num(uw.get('dmgplus1'), 0)
    return {
        'name': up.get('Name', ui.get('name', uid)), 'model': (ui.get('file') or ''), 'scale': num(ui.get('modelScale'), 1),
        'sel_scale': num(ui.get('scale'), 1), 'tint': [num(ui.get('red'), 255), num(ui.get('green'), 255),
                                                         num(ui.get('blue'), 255)],
        'hp': num(ub.get('HP'), 100), 'mp': num(ub.get('manaN'), 0), 'armor': num(ub.get('def'), 0),
        'speed': num(ub.get('spd'), 0), 'fly': num(ud.get('moveHeight'), 0), 'move_type': ud.get('movetp', ''),
        'damage': plus + dice * (sides + 1) / 2.0, 'cool': num(uw.get('cool1'), 1.5), 'range': num(uw.get('rangeN1'), 100),
        'weap': uw.get('weapTp1', ''), 'missile': (up.get('Missileart', '') or '').split(',')[0],
        'abilities': abl, 'hero_abilities': habl, 'dummy': 'Aloc' in abl, 'invuln': 'Avul' in abl,
        'level': num(ub.get('level'), 1), 'collision': num(ud.get('collision'), 32),
        'hero': uid[:1].isupper() and uid in {h['unit'] for h in HEROES},
    }


def mkey(p):
    p = str(p).replace('\\\\', '\\').replace('\\', '/').strip().lower()
    return re.sub(r'\.(mdl|mdx)$', '', p)


def main():
    os.makedirs(OUT, exist_ok=True)
    abil_ids = (FCC & set(AD)) | HERO_AB
    unit_ids = {u for u in FCC if u in UI or u in UB} | {h['unit'] for h in HEROES}
    units = {}
    for u in sorted(unit_ids):
        d = unit(u)
        if d:
            units[u] = d
            abil_ids |= set(d['abilities']) & set(AD)
    abils = {a: ability(a) for a in sorted(abil_ids)}
    abils = {k: v for k, v in abils.items() if v}
    # модели: юниты, арт способностей, строки в коде
    models = set()
    for u in units.values():
        if u['model']:
            models.add(mkey(u['model']))
        if u['missile']:
            models.add(mkey(u['missile']))
    for a in abils.values():
        for k in ('missile', 'effect', 'target', 'caster', 'special', 'area'):
            if a['art'][k]:
                models.add(mkey(a['art'][k]))
    for s in STRS:
        if re.search(r'\.(mdl|mdx)$', s, re.I):
            models.add(mkey(s))
    models.discard('')
    mp = MPQ(MAP)
    files = {}
    for m in models:
        for ext in ('.mdx', '.mdl'):
            nm = m.replace('/', '\\') + ext
            if mp.has(nm):
                files[m] = nm
                break
    # модели героев (akame.mdl и т. п.) уже есть в game/heroes
    hero_models = {mkey(h['model']): h['id'] for h in HEROES}
    in_map, base = {}, []
    for m in sorted(models):
        if m in hero_models:
            continue
        if m in files:
            in_map[m] = files[m]
        else:
            base.append(m)
    # звуки
    snd_dir = OUT + 'sounds/'
    os.makedirs(snd_dir, exist_ok=True)
    sounds = {}
    for s in STRS:
        if re.search(r'\.(mp3|wav)$', s, re.I):
            path = s.replace('\\\\', '\\')
            data = mp.read(path)
            key = path.replace('\\', '/').lower()
            if data:
                fn = re.sub(r'[^a-z0-9_.-]', '_', key.split('/')[-1])
                open(snd_dir + fn, 'wb').write(data)
                sounds[key] = 'res://w3/sounds/' + fn
            else:
                sounds[key] = ''
    data = {'abilities': abils, 'units': units, 'hero_models': hero_models,
            'models_map': sorted(in_map), 'models_base': base, 'sounds': sounds}
    json.dump(data, open(OUT + 'w3_data.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=0)
    json.dump({'map': in_map, 'base': base}, open(OUT + 'models_needed.json', 'w'), indent=1)
    print('abilities', len(abils), 'units', len(units), 'models map', len(in_map), 'base', len(base),
          'sounds', len(sounds), 'missing sounds', sum(1 for v in sounds.values() if not v))


if __name__ == '__main__':
    main()

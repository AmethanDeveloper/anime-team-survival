# -*- coding: utf-8 -*-
"""Герои карты Anime Team Survival 4.9v -> data_heroes.gd.
Берёт heroes_map.json (числа карты) и kits.py (какая способность какого типа), пересчитывает в масштаб игры.
Запуск: python gen_heroes.py <heroes_map.json> <путь к game/scripts/data_heroes.gd>"""
import json
import os
import re
import sys

from kits import KITS

ORDER = ["akame", "esdeath", "ichigo", "miyuki", "shiro", "origami", "archer", "asuna", "brs", "est", "erza", "inori",
         "kirito", "kotori", "kurumi", "natsu", "misaka", "miku", "sinon", "shana", "shinobu", "sephiroth", "saber",
         "shiki", "tamamo", "tina", "tohka", "tsurara", "wrs", "yaya", "yuu", "yoshino"]
KEYS = ["q", "w", "e", "r", "d"]


def clamp(v, a, b):
    return max(a, min(b, v))


def r5(v):
    return int(round(v / 5.0) * 5)


def r1(v, n=1):
    return round(v, n)


# ---------------------------------------------------------------- характеристики героя
def hero_stats(h):
    prim = h['primary']
    melee = h['weap'] == 'normal' or h['range'] < 300
    out = {"primary": prim}
    for a in ("str", "agi", "int"):
        if a == prim:
            out[a] = float(clamp(round(h[a]), 12, 18))
            out[a + "_lvl"] = r1(clamp(h[a + "_lvl"] * 1.1, 2.6, 4.0))
        else:
            out[a] = float(clamp(round(h[a]), 2, 15))
            out[a + "_lvl"] = r1(clamp(h[a + "_lvl"], 0.8, 3.0))
    out["hp"] = float(r5((340 if melee else 310) + min(h['hp'], 500) * 0.08))
    out["mp"] = float(r5(150 + min(h['mana'], 400) * 0.1))
    avg = h['dmg_base'] + h['dice'] * (h['sides'] + 1) / 2.0
    out["damage"] = float(round(clamp(20 + avg * 0.15, 20, 28)))
    out["armor"] = float(clamp(round((h['armor'] * 0.5 + 1) * 2) / 2.0, 1, 6))
    if melee:
        out["range"] = r1(clamp(h['range'] / 60.0, 2.0, 3.0))
    else:
        out["range"] = r1(clamp(h['range'] / 100.0 + 1.0, 7.0, 11.0))
    out["cd"] = r1(clamp(h['cool'] * 0.95, 1.0, 2.0), 2)
    out["speed"] = r1(clamp(h['speed'] / 46.0, 6.8, 8.4))
    out["ranged"] = not melee
    return out


# ---------------------------------------------------------------- способности
ATTR_RE = r'(str(?:ength|enght|eght)?|agi(?:lity|t)?|int(?:elligence|i)?)'


def attr_mix(desc, prim):
    """Какими атрибутами бьёт способность в карте (соотношение)."""
    d = desc.split(',[')[0].split('",')[0]
    m = re.search(r'\[(?:Damage[^\]]*|Dagame|DMG)\](.*?)(?:\[|$)', d, re.I)
    seg = m.group(1) if m else d
    found = {}
    for mm in re.finditer(r'([\d.]+)\s*x\s*' + ATTR_RE, seg, re.I):
        k = mm.group(2)[:3].lower()
        found[k] = max(found.get(k, 0), float(mm.group(1)) or 1.0)
    for mm in re.finditer(ATTR_RE + r'\s*x\s*([\d.]+)', seg, re.I):
        k = mm.group(1)[:3].lower()
        found.setdefault(k, max(float(mm.group(2)), 1.0))
    for mm in re.finditer(ATTR_RE, seg, re.I):
        found.setdefault(mm.group(1)[:3].lower(), 1.0)
    if not found:
        return {prim: 1.0}
    tot = sum(found.values())
    return {k: v / tot for k, v in found.items()}


BUDGET = {  # суммарный коэффициент атрибутов за применение
    "line": (2.0, 3.2, 8.0), "bolt": (2.4, 3.6, 9.0), "aoe_point": (2.0, 3.4, 7.0), "nova": (1.8, 3.0, 6.5),
    "leap_strike": (1.6, 3.0, 7.0), "slashes": (2.4, 4.8, 9.6), "ice_blocks": (3.2, 3.2, 4.0),
}
DEFAULT_SFX = {"line": "slash_heavy", "bolt": "slash_heavy", "aoe_point": "crystal_break", "nova": "slash_heavy",
               "leap_strike": "slash_heavy", "slashes": "swing", "empower": "buff_up", "transform": "transform",
               "blink": "blink", "ice_blocks": "ice_shatter"}
TARGET = {"line": "point", "leap_strike": "point", "aoe_point": "point", "blink": "point", "ice_blocks": "point",
          "mugetsu": "point", "bolt": "unit"}


def find_src(h, src):
    if src is None:
        return {}
    if src == "D":
        return h['set_abilities'][0] if h['set_abilities'] else {}
    if src.startswith("in:"):
        code = src[3:]
        for a in h['innate']:
            if a['code'] == code or a['id'] == code:
                return a
        return {}
    for a in h['abilities']:
        if a['hotkey'] == src:
            return a
    return {}


def build_ability(h, slot, kit):
    k = dict(kit)
    m = find_src(h, k.pop("src", None))
    typ = k.pop("type")
    name = k.pop("name")
    desc = k.pop("desc", "")
    color = k.pop("color", h['color'])
    si = KEYS.index(slot)
    tier = 2 if slot == "d" else (1 if slot == "r" else 0)
    cool = k.pop("cool", m.get('cool', 0))
    cost = k.pop("cost", m.get('cost', 0))
    rng = k.pop("range", None)
    attr = k.pop("attr", None)
    a = {"name": name, "type": typ, "target": TARGET.get(typ, "none")}
    # перезарядка и мана
    if slot == "d":
        a["cd"] = float(round(clamp((cool or 110) * 0.75, 70, 100)))
        a["mana"] = 100.0 if not cost else 150.0
        a["set"] = True
    elif slot == "r":
        a["cd"] = float(round(clamp((cool or 60) * 0.7, 35, 60)))
        a["mana"] = float(r5(clamp((cost or 300) * 0.4, 120, 220)))
        a["ult"] = True
    else:
        a["cd"] = float(round(clamp((cool or 30) / 3.2, 6, 14)))
        a["mana"] = float(r5(clamp((cost or 80) * 0.8, 40, 120)))
    if typ == "passive":
        a["cd"] = 0.0
        a["mana"] = 0.0
    # дальность
    def dist(default, lo, hi):
        if rng is not None:
            return float(rng) if rng < 60 else r1(clamp(rng / 100.0, lo, hi))
        mr = m.get('range', 0)
        return r1(clamp(mr / 100.0, lo, hi)) if mr and mr > 150 else default
    if typ == "line":
        a["range"] = dist(26.0 if tier == 2 else 16.0, 12.0, 26.0 if tier == 2 else 22.0)
        a.setdefault("width", 3.2)
        a.setdefault("speed", 30.0)
    elif typ in ("bolt",):
        a["range"] = dist(14.0, 10.0, 18.0)
    elif typ in ("aoe_point", "ice_blocks"):
        a["range"] = dist(15.0, 10.0, 18.0)
    elif typ == "leap_strike":
        a["range"] = dist(12.0, 8.0, 16.0)
    elif typ == "blink":
        a["range"] = dist(12.0, 8.0, 14.0)
    elif typ == "mugetsu":
        a["range"] = 26.0
    # радиус
    if typ in ("aoe_point", "nova", "slashes", "leap_strike", "ice_blocks"):
        ma = m.get('area', 0) or 0
        a["radius"] = r1(clamp(ma / 100.0, 3.0, 7.0)) if ma > 60 else {"aoe_point": 4.5, "nova": 5.5, "slashes": 5.0,
                                                                         "leap_strike": 3.6, "ice_blocks": 5.0}[typ]
    # урон
    if typ in BUDGET:
        mix = attr or attr_mix(m.get('desc', ''), h['primary'])
        total = BUDGET[typ][tier]
        n = 1
        if typ == "slashes":
            n = int(k.get("hits", 8))
            total *= 1.15
        elif typ in ("aoe_point", "nova"):
            n = int(k.get("waves", 1))
            total *= 1.0 + 0.15 * (n - 1)
        elif typ == "line":
            n = int(k.get("shots", 1))
        for at, f in mix.items():
            a[at] = r1(total * f / n, 2)
    # усиления: удары с доп. уроном
    a["color"] = tuple(color)
    a["sfx"] = k.pop("sfx", DEFAULT_SFX.get(typ, ""))
    if typ in ("empower", "transform", "metamorphosis", "time_stop"):
        a.setdefault("duration", k.get("duration", 10.0))
    a.update(k)
    a["desc"] = desc
    a["map"] = m.get('name', '')
    a["art"] = m.get('art', '')
    return a


def old_abilities(path):
    """Способности Акаме, Эсдес и Ичиго из старого data.gd — их механика уже сделана под карту."""
    s = open(path, encoding='utf-8').read()
    i = s.index('const ABILITIES := {')
    j = s.index('\n}\n', i)
    body = s[i + len('const ABILITIES := '):j + 2]
    body = re.sub(r'#[^\n]*', '', body)
    body = re.sub(r'Color\(([^)]*)\)', r'(\1)', body)
    body = body.replace('true', 'True').replace('false', 'False')
    return eval(body)


def gd(v, ind=1):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return repr(round(v, 4))
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, tuple):
        return "Color(%s)" % ", ".join(repr(round(float(x), 3)) for x in v)
    if isinstance(v, list):
        return "[" + ", ".join(gd(x, ind) for x in v) + "]"
    if isinstance(v, dict):
        items = ", ".join("%s: %s" % (json.dumps(kk, ensure_ascii=False), gd(vv, ind + 1)) for kk, vv in v.items())
        return "{" + items + "}"
    raise TypeError(v)


FALLBACK = {"str": "res://models/hero_swordsman.glb", "agi": "res://models/hero_assassin.glb",
            "int": "res://models/hero_sorceress.glb"}
GOALS = {
    "str": ["antimagic", "soul_nature", "set_%s", "lightning_sword", "health_staff", "seven_senses", "rejuvenation"],
    "agi": ["antimagic", "soul_nature", "set_%s", "lightning_sword", "sinon_crit", "lost_relic", "rejuvenation"],
    "int": ["antimagic", "soul_nature", "set_%s", "water_shield", "gem_wishes", "subzero", "rejuvenation"],
}


import w3kit  # noqa: E402
W3DATA = json.load(open(os.environ.get('W3DATA', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game', 'w3', 'w3_data.json')), encoding='utf-8'))
LEGACY = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'legacy_kits.json'), encoding='utf-8'))
w3kit.load_books(os.environ.get('W3SLK', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'map_ext', 'Units', 'AbilityData.slk')))
W3LISTS = w3kit.load_target_lists(os.environ.get('W3ABIL', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game', 'scripts', 'w3', 'w3_abil.gd')))


def main(src_json, out_gd, old_data_gd):
    H = {h['id']: h for h in json.load(open(src_json, encoding='utf-8'))}
    old = old_abilities(old_data_gd)
    heroes = {}
    abilities = {}
    report = []
    for hid in ORDER:
        h = H[hid]
        kit = KITS[hid]
        st = hero_stats(h)
        d = {"name": h['name'], "title": h['title'], "series": h['series'], "role": kit.get("role", ""),
             "fallback_model": FALLBACK[st['primary']], "color": tuple(h['color'])}
        d.update(st)
        d.update(kit.get("passive", {}))
        ids = []
        # способности как в карте: Q W E R, врождённая [D], способность сета [T]
        w3 = w3kit.build(h, kit, W3DATA, W3LISTS, tuple(h['color']))
        book = []
        for slot in w3kit.SLOTS:
            aid = "%s_%s" % (hid, slot)
            if slot in w3:
                abilities[aid] = w3[slot]
                book += abilities[aid].pop("book", [])
            else:
                # в карте этого слота нет — остаётся прежняя способность игры (у сета прежний ключ _d)
                leg = LEGACY.get("%s_%s" % (hid, "d" if slot == "t" else slot))
                if not leg or slot == "d":
                    leg = {"name": "—", "type": "empty", "target": "none", "mana": 0.0, "cd": 0.0, "desc": ""}
                leg = dict(leg)
                for ck, cv in list(leg.items()):
                    if isinstance(cv, list) and len(cv) in (3, 4) and all(isinstance(x, (int, float)) for x in cv) and ck == "color":
                        leg[ck] = tuple(cv)
                if slot == "t":
                    leg["set"] = True
                abilities[aid] = leg
            ids.append(aid)
        # способности из книги заклинаний — слоты 6.. (свои клавиши)
        for k, b in enumerate(book):
            aid = "%s_b%d" % (hid, k + 1)
            abilities[aid] = b
            ids.append(aid)
        d["abilities"] = ids
        d["passive"] = kit.get("passive_text", "")
        d["map_unit"] = h['unit']
        heroes[hid] = d
        report.append((hid, st, [(abilities[i]['type'], abilities[i].get('target'), abilities[i]['name']) for i in ids]))
    lines = ["class_name HeroData",
             "## Герои карты Anime Team Survival 4.9v — генерируется tools/wc3_import/gen_heroes.py, руками не править.",
             "## Характеристики пересчитаны из карты, способности подобраны из типов, которые умеет abilities.gd.", "",
             "const HERO_ORDER := %s" % gd(ORDER), "", "const HEROES := {"]
    for hid in ORDER:
        lines.append('\t"%s": %s,' % (hid, gd(heroes[hid])))
    lines.append("}")
    lines.append("")
    lines.append("const ABILITIES := {")
    for hid in ORDER:
        for aid in heroes[hid]["abilities"]:
            lines.append('\t"%s": %s,' % (aid, gd(abilities[aid])))
    lines.append("}")
    lines.append("")
    lines.append("const BOT_GOALS := {")
    for hid in ORDER:
        g = [x % hid if "%s" in x else x for x in GOALS[heroes[hid]['primary']]]
        lines.append('\t"%s": %s,' % (hid, gd(g)))
    lines.append("}")
    open(out_gd, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    return heroes, abilities, report


if __name__ == "__main__":
    heroes, abilities, report = main(sys.argv[1], sys.argv[2], sys.argv[3])
    for hid, st, ab in report:
        print(hid, {k: st[k] for k in ("primary", "str", "agi", "int", "hp", "damage", "range", "ranged")}, ab)

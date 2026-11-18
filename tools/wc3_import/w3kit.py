# -*- coding: utf-8 -*-
"""Способности героев «как в карте»: слоты Q W E R + врождённая [D] + способность сета [T].

Каждая запись — тип "w3": действие выполняют триггеры карты (game/scripts/w3/w3_map.gd)
и базовая способность WC3 (W3Abil.cast_base) по данным из game/w3/w3_data.json.
"""
import re

U = 1.0 / 48.0
SLOTS = ['q', 'w', 'e', 'r', 'd', 't']

TAGS = {
    'damage': 'Урон', 'aoe': 'Область', 'damage aoe': 'Область урона', 'range': 'Дальность', 'distance': 'Дальность',
    'duration': 'Длительность', 'cooldown': 'Перезарядка', 'coolodwn': 'Перезарядка', 'effect': 'Эффект',
    'description': 'Описание', 'descripcion': 'Описание', 'movement speed': 'Скорость бега',
    'bonusdamage': 'Бонус урона', 'target': 'Цель', 'casting time': 'Подготовка', 'casting': 'Подготовка',
    'bullet': 'Снаряды', 'regeneration': 'Регенерация', 'attack speed': 'Скорость атаки', 'chance-hit': 'Шанс',
    'chance': 'Шанс', 'probability': 'Вероятность', 'slash': 'Разрезы', 'armor-bonus': 'Бонус брони',
    'armor': 'Броня', 'extra armor': 'Доп. броня', 'stun': 'Оглушение', 'debuff': 'Ослабление',
    'duration poison': 'Длительность яда', 'blocks': 'Блоки', 'strength': 'Сила', 'bonusdefense': 'Бонус защиты',
    'bonushealth': 'Бонус здоровья', 'health bonus': 'Бонус здоровья', 'slow factor': 'Замедление',
    'critical hit': 'Критический удар', 'critical-hit': 'Критический удар', 'evasion': 'Уклонение',
    'chance to miss hit': 'Шанс промаха врага', 'max': 'Максимум', 'jumps': 'Прыжки', 'illusion': 'Иллюзии',
    'manadrain': 'Кража маны', 'manaregeneration': 'Восст. маны', 'explosion-damage': 'Урон взрыва',
    'health-absorb': 'Поглощение здоровья', 'number-units': 'Число юнитов', 'strenght-bonus': 'Бонус силы',
    'streght-bonus': 'Бонус силы', 'mana absorb': 'Поглощение маны', 'hero damage': 'Урон по героям',
    'range bonus': 'Бонус дальности', 'pasive': 'Пассивно', 'passive': 'Пассивно', 'total amount': 'Всего',
    'amount': 'Количество', 'heal': 'Лечение', 'healing': 'Лечение', 'mana': 'Мана', 'summon': 'Призыв',
}
WORDS = [(r'\bStr\b', 'Сила'), (r'\bAgi\b', 'Ловкость'), (r'\bInt\b', 'Интеллект'), (r'\bLevel\b', 'ур.'),
         (r'(\d)\s*s\b', r'\1 с'), (r'\bsec(onds?)?\b', 'с'), (r'\beach\b', 'каждый'), (r'\bper\b', 'за'),
         (r'\bHero(es)?\b', 'герой'), (r'\bInf\b', '∞')]


def strip_codes(s):
    s = re.sub(r'\|c[0-9a-fA-F]{8}', '', s or '')
    s = s.replace('|r', '').replace('|n', '\n')
    return s.strip()


def translate(desc):
    """Подсказка карты (теги [Damage] ... через запятую по уровням) -> русская строка уровня 1."""
    s = strip_codes(desc).split(',[')[0]
    parts = re.split(r'\[([^\]]+)\]', s)
    out = []
    lead = parts[0].strip()
    if lead:
        out.append(lead)
    for i in range(1, len(parts), 2):
        tag = parts[i].strip()
        val = parts[i + 1].strip() if i + 1 < len(parts) else ''
        name = TAGS.get(tag.lower(), tag)
        for a, b in WORDS:
            val = re.sub(a, b, val)
        val = val.replace(' x ', ' × ').replace(')x', ')×')
        out.append('%s: %s' % (name, val) if val else name)
    return '\n'.join(out)


def load_target_lists(path):
    src = open(path, encoding='utf-8').read()
    lists = {}
    for nm in ('UNIT_T', 'POINT_T', 'NONE_T', 'PASSIVE_T'):
        m = re.search(r'const %s := \[(.*?)\]' % nm, src, re.S)
        lists[nm] = re.findall(r'"(\w+)"', m.group(1)) if m else []
    return lists


def target_of(code, lv, lists):
    known = lists['UNIT_T'] + lists['POINT_T'] + lists['NONE_T'] + ['ANcl']
    if code not in known and not float(lv.get('cool', 0) or 0) and not float(lv.get('cost', 0) or 0):
        return 'passive'
    if code == 'ANcl':
        b = int(lv.get('b', 0) or 0)
        return 'unit' if b == 1 else ('point' if b in (2, 3) else 'none')
    if code in lists['UNIT_T']:
        return 'unit'
    if code in lists['POINT_T']:
        return 'point'
    if code in lists['PASSIVE_T']:
        return 'passive'
    return 'none'


def slot_sources(h):
    """Какая способность карты в каком слоте."""
    by_key = {}
    rest = []
    for a in h['abilities']:
        k = (a.get('hotkey') or '').lower()
        if k in ('q', 'w', 'e', 'r') and k not in by_key:
            by_key[k] = a
        else:
            rest.append(a)
    for k in ('q', 'w', 'e', 'r'):
        if k not in by_key and rest:
            by_key[k] = rest.pop(0)
    innate = [a for a in (h.get('innate') or []) if a]
    d = None
    for a in innate:
        if (a.get('hotkey') or '').upper() == 'D':
            d = a
            break
    if d is None and innate:
        d = innate[0]
    t = (h.get('set_abilities') or [None])[0]
    if t is None:
        for a in innate:
            if a is not d and (a.get('hotkey') or '').upper() == 'T':
                t = a
    by_key['d'] = d
    by_key['t'] = t
    return by_key


def build(h, kit, w3data, lists, color):
    src = slot_sources(h)
    out = {}
    for slot in SLOTS:
        m = src.get(slot)
        if not m:
            continue
        ad = w3data['abilities'].get(m['id'])
        if not ad:
            continue
        lv = ad['levels'][0] if ad['levels'] else {}
        code = ad['code']
        tgt = target_of(code, lv, lists)
        # русское название из прежних наборов (там оно взято из той же способности карты)
        name = m['name']
        if slot in ('q', 'w', 'e', 'r') and slot in kit:
            name = kit[slot]['name']
        elif slot == 't' and 'd' in kit:
            name = kit['d']['name']
        rng = float(lv.get('rng', 0) or 0)
        area = float(lv.get('area', 0) or 0)
        a = {
            'name': name, 'type': 'passive' if tgt == 'passive' else 'w3', 'target': 'none' if tgt == 'passive' else tgt,
            'w3': m['id'], 'code': code, 'mana': float(lv.get('cost', 0) or 0), 'cd': float(lv.get('cool', 0) or 0),
            'range': round(max(rng * U, 3.0) if tgt in ('unit', 'point') else rng * U, 2),
            'radius': round(area * U, 2), 'color': color, 'map': m['name'],
            'desc': translate(m.get('desc') or ''), 'art': m.get('art') or '',
        }
        if slot == 't':
            a['set'] = True
        if slot == 'd':
            a['innate'] = True
        if tgt == 'passive':
            a['cd'] = 0.0
            a['mana'] = 0.0
        if code == 'Aspb':
            # книга заклинаний: внутри — свои способности (в WC3 открывается подменю)
            a['type'] = 'book'
            a['target'] = 'none'
            a['cd'] = 0.0
            a['mana'] = 0.0
            inner = []
            used = set('QWERDTABCHS')
            free = [k for k in 'FGVXZ']
            raw = w3data['abilities'][m['id']]
            for iid in BOOKS.get(m['id'], []):
                ia = w3data['abilities'].get(iid)
                if not ia:
                    continue
                ilv = ia['levels'][0] if ia['levels'] else {}
                itg = target_of(ia['code'], ilv, lists)
                hk = (ia.get('hotkey') or '').upper()[:1]
                if not hk or hk in used:
                    hk = free.pop(0) if free else ''
                used.add(hk)
                if hk in free:
                    free.remove(hk)
                irng = float(ilv.get('rng', 0) or 0)
                inner.append({
                    'name': re.sub(r'\s*\(\w\)\s*$|\[\w\]\s*$', '', ia.get('tip') or ia.get('name') or iid).strip(), 'type': 'passive' if itg == 'passive' else 'w3',
                    'target': 'none' if itg == 'passive' else itg, 'w3': iid, 'code': ia['code'],
                    'mana': float(ilv.get('cost', 0) or 0), 'cd': float(ilv.get('cool', 0) or 0),
                    'range': round(max(irng * U, 3.0) if itg in ('unit', 'point') else irng * U, 2),
                    'radius': round(float(ilv.get('area', 0) or 0) * U, 2), 'color': color, 'map': ia.get('name', ''),
                    'desc': translate(ia.get('ubertip') or ''), 'art': (ia.get('art') or {}).get('icon', ''), 'book_of': 4 if slot == 'd' else 5,
                    'hotkey': hk})
            a['book'] = inner
        out[slot] = a
    return out


BOOKS = {}


def load_books(slk_path):
    import os
    from w3data import parse_slk
    if not os.path.isfile(slk_path):
        return
    ad = parse_slk(slk_path)
    for k, r in ad.items():
        if r.get('code') == 'Aspb':
            BOOKS[k] = [x.strip() for x in (r.get('DataA1') or '').split(',') if x.strip()]

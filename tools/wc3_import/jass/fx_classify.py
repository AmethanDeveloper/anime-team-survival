# -*- coding: utf-8 -*-
"""Классы эффектов карты для замены готовыми эффектами (VfxLib): взрыв, удар/вспышка, молния, снаряд, волна.

Для каждой модели из fx/*.fx.json считает:
  kind  — explosion | impact | hit | zap | orb | javelin | wave | keep
  col   — основной цвет (по цветам частиц и текстурам, ярким пикселям)
  size  — размер модели в её единицах (для масштаба замены)
Результат дописывается в fx.json каждой модели (поле "vfx"), дальше pack_w3.py кладёт его в w3_fx.json.

Запуск: python fx_classify.py <папка fx>
"""
import colorsys
import io
import json
import os
import re
import struct
import sys

from PIL import Image

KEEP = re.compile(r'aura|circle|clockwise|cronosphere|timer|chess|pawn|rook|bishop|queen|king|knight|crystal|rocks|'
                  r'wing|sword|katana|blade_purple|bluesword|jinggangjian|xuanyanjian|byakugan|erza|ichigo|niutou|'
                  r'units_|hero_|kissshot|saberextra|tina_sprout|type_2020|yoshinon|alter_tooka|ls_you|tobiichi|'
                  r'buildings_|doodads_|environment_|note|gearwheel|tornado|shield|mine|portal|haze|field|'
                  r'harvest|healingwater|enchantment|supershiny|levelup|retraining|resurrect|revive|reincarnation|'
                  r'magiccircle|magic_cast|fuwen|jianzhen|jiejin|lingyabao|mfqwd|mfz|niaoju|qinglong|whitetiger|'
                  r'phoenix_wing|remilia|dummy|effect_reiatsu|valkkame|zm_chib|cosmic|galaxy|devil_aura|blackhole|'
                  r'hellhole|eclipse|mist|flame_aura|firey|akihafire|shanafire|smoke$|dust$|blind|timeupheaval|'
                  r'hauntedmine|skyring|darkelf|glaciar|illusions|frozencaster|tenpa_cast|holyblessing|devotion|'
                  r'frostarmor|lightningshield|vampiricaura|spirittouch|purgebuff|doomtarget|markofchaos|aihe|ailm|'
                  r'vamppotion|starfallcaster|magicsentry|defendcaster|spiritwalkerchange|howltarget|silence')
WAVE = re.compile(r'wave|getsuga|wake|sonicboom|slash|sweep|cero|daoguang|shinku|kirito_stbs|crushing|shockwave|'
                  r'breathoffire|reddragon|carrion|stampedemissile$')
JAVELIN = re.compile(r'arrow|laser|lance|spear|javelin|bullet|rifle(?!impact)|rocket|grenade|cannon(?!s)|ray$|'
                     r'digital_ray|ioncannon|brs_cannon|lasercannon|mirrorzi|baibullet')
ORB = re.compile(r'missile|bolt(?!impact|target)|ball|orb|energybolt|magic_missile|bomb$|flamebomb|meteor|'
                 r'deathcoil|shadowstrike|absorbmana|annihilation|holysmite')
ZAP = re.compile(r'lightning|thunder(?!clap)|zap|electric|shock|monsoon|ss2_lightning|eyeofzeus|ct_energy')
EXPLOSION = re.compile(r'explo|nova|stomp|blast|boom|nuke|nuclear|bomb|eruption|erruption|burst|slam|volcano|'
                       r'thunderclap|warstomp|flamestrike|mushroom|chaos|bijuu|solar|judgement|meteor|death_spell|'
                       r'flamegroundex|magmaburst|firerelease|firetornado|apocalypse|devilslam|hailstorm|'
                       r'freezingring|freezingsplinter|blizzard|iceslam|frost_spike|aquaspike|icebern|frostnova|'
                       r'freezingbreath|stampedemissiledeath|cherry_blossom|legionstrike|lightstrikearray|'
                       r'littledark|dustexplosion|abominationexplosion|alice_doll|t_bloodex|asuma|ancientexplode|'
                       r'red_explosion|boom_red|stkxs|darknessbomb|a_bomb|firebombtarget|nagadeath')
HIT = re.compile(r'impact|damage|hit|strike|flare|special|target|blink|cleave|blood|spark|flash|burst|ghost|'
                 r'smite|basicstrike|attack|caster|redlightgas|holynova|lightnova|heartburst')


def kind_of(name):
    n = name.lower()
    for p in ('abilities_spells_', 'abilities_weapons_', 'war3mapimported_', 'objects_spawnmodels_'):
        n = n.replace(p, '')
    if re.search(r'firey|flame_aura|flame_haze|shanafire|akihafire|natsuraienryuufire|buildingfire|smallflamespawn', n):
        return 'fire'
    if KEEP.search(n) and not EXPLOSION.search(n) or 'awaken' in n:
        return 'keep'
    if re.search(r'(impact|target|damage|death|specialart|blood|caster|targetart)$', n):
        if EXPLOSION.search(n):
            return 'explosion'
        return 'zap' if ZAP.search(n) else 'hit'
    if 'shockwave' in n:
        return 'wave'
    if ZAP.search(n) and not EXPLOSION.search(n):
        return 'zap'
    if WAVE.search(n):
        return 'wave'
    if JAVELIN.search(n):
        return 'javelin'
    if EXPLOSION.search(n):
        return 'explosion'
    if ORB.search(n):
        return 'orb'
    if HIT.search(n):
        return 'hit'
    return 'unknown'


def glb_info(path):
    """Размер по min/max вершин и средний яркий цвет встроенных текстур."""
    data = open(path, 'rb').read()
    if data[:4] != b'glTF':
        return 0.0, []
    jl = struct.unpack_from('<I', data, 12)[0]
    js = json.loads(data[20:20 + jl])
    binoff = 20 + jl + 8
    size = 0.0
    for acc in js.get('accessors', []):
        if acc.get('type') == 'VEC3' and 'min' in acc and 'max' in acc:
            mn, mx = acc['min'], acc['max']
            ext = max(mx[0] - mn[0], mx[2] - mn[2], mx[1] - mn[1])
            if ext < 1e5:
                size = max(size, ext)
    imgs = []
    for im in js.get('images', []):
        bv = js['bufferViews'][im['bufferView']] if 'bufferView' in im else None
        if bv is None:
            continue
        b = data[binoff + bv.get('byteOffset', 0):binoff + bv.get('byteOffset', 0) + bv['byteLength']]
        try:
            imgs.append(Image.open(io.BytesIO(b)).convert('RGBA'))
        except Exception:
            pass
    return size, imgs


def bright_avg(imgs):
    """Цвет ярких непрозрачных пикселей (свечение), а не тёмного фона."""
    r = g = b = w = 0.0
    for im in imgs:
        im = im.resize((32, 32))
        for (pr, pg, pb, pa) in (im.get_flattened_data() if hasattr(im, 'get_flattened_data') else im.getdata()):
            lum = max(pr, pg, pb) / 255.0
            k = (pa / 255.0) * lum * lum
            r += pr * k
            g += pg * k
            b += pb * k
            w += k * 255.0
    if w <= 0:
        return None
    return [r / w, g / w, b / w]


def saturate(c):
    h, s, v = colorsys.rgb_to_hsv(*c)
    return list(colorsys.hsv_to_rgb(h, min(1.0, s * 1.25), max(0.75, v)))


def main():
    fx = sys.argv[1]
    stats = {}
    for fn in sorted(os.listdir(fx)):
        if not fn.endswith('.fx.json'):
            continue
        name = fn[:-8]
        p = os.path.join(fx, fn)
        d = json.load(open(p))
        kind = kind_of(name)
        size = 0.0
        imgs = []
        if d.get('glb') and os.path.exists(os.path.join(fx, d['glb'])):
            size, imgs = glb_info(os.path.join(fx, d['glb']))
        cols = []
        for e in d.get('emitters', []):
            reach = float(e.get('speed', 0)) * float(e.get('lifespan', 0)) * 2 + max(e.get('scaling', [0]) or [0]) * 2
            size = max(size, reach)
            for c, a in zip(e.get('colors', []), e.get('alphas', [])):
                if a > 30:
                    cols.append(([c[2], c[1], c[0]], a / 255.0))   # в данных порядок B, G, R
            t = e.get('tex')
            if t and os.path.exists(os.path.join(fx, t)):
                try:
                    imgs.append(Image.open(os.path.join(fx, t)).convert('RGBA'))
                except Exception:
                    pass
        tex = bright_avg(imgs)
        col = None
        if cols:
            w = sum(a for _, a in cols)
            ec = [sum(c[i] * a for c, a in cols) / w for i in range(3)]
            # цвет частиц умножается на текстуру
            col = [ec[i] * (tex[i] if tex else 1.0) for i in range(3)]
            m = max(col)
            if m > 0:
                col = [x / m for x in col]
        elif tex:
            m = max(tex)
            col = [x / m for x in tex] if m > 0 else None
        if col is None:
            col = [1.0, 0.9, 0.7]
        col = saturate(col)
        d['vfx'] = {'kind': kind, 'col': [round(x, 3) for x in col], 'size': round(size, 3)}
        json.dump(d, open(p, 'w'))
        stats.setdefault(kind, []).append(name)
        if 'stampedemissiledeath' in name:
            d['vfx']['kind'] = 'impact'
            json.dump(d, open(p, 'w'))
    for k, v in sorted(stats.items()):
        print(k, len(v), ', '.join(x.replace('war3mapimported_', 'I:').replace('abilities_', '') for x in v))


if __name__ == '__main__':
    main()

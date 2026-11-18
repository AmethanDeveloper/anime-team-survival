"""
Синтез звуковых эффектов для Anime Team Survival (собственные звуки, без чужих записей).
Запуск: python make_sfx.py <папка_вывода>
"""
import os, sys
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter

SR = 22050
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "game", "audio", "sfx")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)


def t(d):
    return np.arange(int(SR * d)) / SR


def env(n, a=0.005, d=0.1, s=0.0, r=0.1, total=None):
    """ADSR по количеству сэмплов."""
    a, d, r = int(a * SR), int(d * SR), int(r * SR)
    total = n
    sus = max(0, total - a - d - r)
    e = np.concatenate([np.linspace(0, 1, max(a, 1)), np.linspace(1, s, max(d, 1)), np.full(sus, s), np.linspace(s, 0, max(r, 1))])
    return np.pad(e, (0, max(0, n - len(e))))[:n]


def exp_env(n, k):
    return np.exp(-np.arange(n) / SR * k)


def noise(d):
    return rng.uniform(-1, 1, int(SR * d))


def lp(x, f):
    b, a = butter(2, min(f / (SR / 2), 0.99), "low")
    return lfilter(b, a, x)


def hp(x, f):
    b, a = butter(2, min(f / (SR / 2), 0.99), "high")
    return lfilter(b, a, x)


def bp(x, lo, hi):
    b, a = butter(2, [lo / (SR / 2), min(hi / (SR / 2), 0.99)], "band")
    return lfilter(b, a, x)


def sweep_filter(x, f0, f1, kind="band", q=0.6):
    """Фильтр с плавающей частотой — блоками."""
    out = np.zeros_like(x)
    n = len(x)
    blk = 256
    zi = None
    for i in range(0, n, blk):
        f = f0 + (f1 - f0) * (i / max(n - 1, 1))
        lo, hi = max(40, f * (1 - q)), min(SR / 2 - 100, f * (1 + q))
        b, a = butter(2, [lo / (SR / 2), hi / (SR / 2)], "band")
        seg = x[i:i + blk]
        if zi is None:
            zi = np.zeros(max(len(a), len(b)) - 1)
        y, zi = lfilter(b, a, seg, zi=zi)
        out[i:i + blk] = y
    return out


def sine(f, d, phase=0.0):
    tt = np.arange(d) / SR if isinstance(d, (int, np.integer)) else t(d)
    if callable(f):
        ph = np.cumsum(f(tt)) / SR * 2 * np.pi
        return np.sin(ph + phase)
    return np.sin(2 * np.pi * f * tt + phase)


def fit(x, n):
    return np.pad(x, (0, max(0, n - len(x))))[:n]


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) + 1e-9
    return x / m * peak


def save(name, x, peak=0.9):
    x = norm(x, peak)
    fade = min(len(x), 200)
    x[-fade:] *= np.linspace(1, 0, fade)
    wavfile.write(os.path.join(OUT, name + ".wav"), SR, (x * 32767).astype(np.int16))
    print("sfx", name, round(len(x) / SR, 2), "s")


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


# ------------------------------------------------------------------ удары и оружие
def swing():
    d = 0.28
    x = sweep_filter(noise(d), 600, 2800, q=0.5) * env(int(SR * d), 0.04, 0.2, 0, 0.04)
    return x


def hit():
    d = 0.22
    n = int(SR * d)
    thump = sine(lambda tt: 160 * np.exp(-tt * 18) + 60, d) * exp_env(n, 22)
    crack = hp(noise(d), 1500) * exp_env(n, 45)
    return mix(thump * 0.9, crack * 0.6)


def slash_heavy():
    d = 0.6
    n = int(SR * d)
    w = sweep_filter(noise(d), 300, 3500, q=0.7) * env(n, 0.06, 0.4, 0, 0.1)
    ring = sine(lambda tt: 2200 - 900 * tt, d) * exp_env(n, 6) * 0.25
    boom = lp(noise(d), 200) * exp_env(n, 8) * 1.5
    return mix(w, ring, boom)


def blink():
    d = 0.4
    n = int(SR * d)
    w = sweep_filter(noise(d), 4000, 400, q=0.5) * env(n, 0.01, 0.3, 0, 0.08)
    sp = sine(lambda tt: 1800 + 2400 * tt, d) * exp_env(n, 10) * 0.3
    return mix(w, sp)


# ------------------------------------------------------------------ лёд
def ice_cast():
    d = 0.7
    n = int(SR * d)
    parts = []
    for k in range(9):
        f = rng.uniform(2200, 5200)
        st = int(rng.uniform(0, 0.35) * SR)
        tone = sine(f, n - st) * exp_env(n - st, rng.uniform(10, 20)) * rng.uniform(0.2, 0.5)
        parts.append(np.pad(tone, (st, 0)))
    shimmer = hp(noise(d), 5000) * env(n, 0.05, 0.4, 0, 0.2) * 0.3
    return mix(*parts, shimmer)


def ice_shatter():
    d = 0.9
    n = int(SR * d)
    crack = hp(noise(d), 2500) * exp_env(n, 9)
    boom = lp(noise(d), 180) * exp_env(n, 6) * 2.0
    tinkles = []
    for k in range(14):
        st = int(rng.uniform(0.02, 0.5) * SR)
        f = rng.uniform(3000, 7000)
        tinkles.append(np.pad(sine(f, 0.12) * exp_env(int(0.12 * SR), 40) * 0.3, (st, 0)))
    return mix(crack, boom, *tinkles)


def freeze():
    d = 0.5
    n = int(SR * d)
    cr = np.zeros(n)
    for k in range(40):
        p = int(rng.uniform(0, 0.4) * SR)
        cr[p:p + 30] += rng.uniform(-1, 1, 30) * rng.uniform(0.3, 1.0)
    cr = hp(cr, 2000)
    tone = sine(lambda tt: 3000 - 1500 * tt, d) * exp_env(n, 6) * 0.2
    return mix(cr, tone)


# ------------------------------------------------------------------ усиления
def buff_up():
    d = 0.8
    n = int(SR * d)
    tone = sine(lambda tt: 220 * (1 + 2.0 * tt), d) * env(n, 0.05, 0.3, 0.5, 0.3)
    tone2 = sine(lambda tt: 330 * (1 + 2.0 * tt), d) * env(n, 0.05, 0.3, 0.4, 0.3) * 0.6
    air = sweep_filter(noise(d), 300, 3000, q=0.4) * env(n, 0.2, 0.3, 0.2, 0.3) * 0.5
    return mix(tone, tone2, air)


def transform():
    d = 1.6
    n = int(SR * d)
    roar = lp(noise(d), 400) * env(n, 0.2, 0.6, 0.6, 0.6) * 1.5
    rise = sine(lambda tt: 70 + 160 * tt, d) * env(n, 0.1, 0.5, 0.7, 0.6)
    harm = sine(lambda tt: 140 + 320 * tt, d) * env(n, 0.3, 0.5, 0.4, 0.6) * 0.4
    burst = hp(noise(d), 800) * fit(np.pad(exp_env(int(0.6 * SR), 5), (int(0.9 * SR), 0)), n) * 0.7
    return mix(roar, rise, harm, burst)


def time_stop():
    d = 2.2
    n = int(SR * d)
    swell = sweep_filter(noise(d), 200, 6000, q=0.3) * np.linspace(0, 1, n) ** 2 * 0.8
    cut = int(1.1 * SR)
    swell[cut:] *= exp_env(n - cut, 30)
    bell = np.zeros(n)
    for f, a in [(523, 1.0), (1046, 0.5), (1569, 0.3), (659, 0.6)]:
        tone = sine(f, n - cut) * exp_env(n - cut, 1.6) * a
        bell[cut:] += tone
    ticks = np.zeros(n)
    for k in range(4):
        p = cut + int((0.25 + k * 0.25) * SR)
        if p + 300 < n:
            ticks[p:p + 300] += hp(noise(300 / SR), 3000) * exp_env(300, 200) * 0.6
    return mix(swell, bell * 0.6, ticks)


def time_resume():
    d = 0.9
    n = int(SR * d)
    glass = hp(noise(d), 3000) * exp_env(n, 7)
    sweep = sine(lambda tt: 1600 - 1200 * tt, d) * exp_env(n, 4) * 0.4
    return mix(glass, sweep)


def mugetsu():
    d = 2.6
    n = int(SR * d)
    boom = lp(noise(d), 120) * env(n, 0.01, 1.4, 0.2, 1.0) * 3.0
    sub = sine(lambda tt: 45 + 20 * np.exp(-tt * 2), d) * env(n, 0.02, 1.5, 0.3, 1.0) * 1.5
    tear = sweep_filter(noise(d), 3000, 200, q=0.6) * env(n, 0.01, 0.8, 0.1, 0.5) * 1.2
    dark = sine(lambda tt: 110 + 5 * np.sin(tt * 30), d) * env(n, 0.3, 0.8, 0.4, 1.0) * 0.4
    return mix(boom, sub, tear, dark)


def poison():
    d = 0.5
    n = int(SR * d)
    bub = np.zeros(n)
    for k in range(8):
        p = int(rng.uniform(0, 0.4) * SR)
        f = rng.uniform(300, 700)
        b = sine(lambda tt: f * (1 + 3 * tt), 0.06) * exp_env(int(0.06 * SR), 40)
        bub[p:p + len(b)] += b[:max(0, min(len(b), n - p))] * 0.5
    hiss = bp(noise(d), 3000, 8000) * env(n, 0.05, 0.3, 0.1, 0.1) * 0.3
    return mix(bub, hiss)


# ------------------------------------------------------------------ мир
def wave_horn():
    d = 1.8
    n = int(SR * d)
    f = lambda tt: 98 + 6 * np.sin(tt * 5)
    x = sine(f, d) + 0.5 * sine(lambda tt: 2 * f(tt), d) + 0.3 * sine(lambda tt: 3 * f(tt), d)
    x = lp(x, 900) * env(n, 0.25, 0.6, 0.7, 0.6)
    return x


def boss_roar():
    d = 1.6
    n = int(SR * d)
    g = noise(d) * (0.6 + 0.4 * sine(lambda tt: 28 + 6 * tt, d))
    x = sweep_filter(g, 300, 900, q=0.6) + lp(noise(d), 150) * 1.5
    return x * env(n, 0.1, 0.6, 0.6, 0.6)


def crystal_hit():
    d = 0.5
    n = int(SR * d)
    x = sine(1760, d) * exp_env(n, 9) + sine(2637, d) * exp_env(n, 12) * 0.5 + hp(noise(d), 4000) * exp_env(n, 40) * 0.4
    return x


def crystal_break():
    d = 2.0
    n = int(SR * d)
    boom = lp(noise(d), 150) * exp_env(n, 2.5) * 2.0
    glass = hp(noise(d), 2500) * exp_env(n, 3)
    tink = []
    for k in range(30):
        st = int(rng.uniform(0.05, 1.2) * SR)
        tink.append(np.pad(sine(rng.uniform(2000, 6000), 0.2) * exp_env(int(0.2 * SR), 25) * 0.25, (st, 0)))
    return mix(boom, glass, *tink)


def portal():
    d = 0.8
    n = int(SR * d)
    w = sine(lambda tt: 200 + 900 * tt, d) * env(n, 0.05, 0.4, 0.2, 0.3) * 0.6
    ph = sweep_filter(noise(d), 500, 4000, q=0.3) * env(n, 0.1, 0.4, 0.2, 0.2) * 0.6
    return mix(w, ph)


def duel_gong():
    d = 3.0
    n = int(SR * d)
    x = np.zeros(n)
    for f, a, k in [(110, 1.0, 1.0), (165, 0.7, 1.4), (247, 0.5, 1.8), (330, 0.4, 2.2), (523, 0.25, 3.0), (740, 0.15, 4)]:
        x += sine(f * (1 + 0.002 * np.sin(np.arange(n) / SR * 3)), d) * exp_env(n, k) * a
    x += lp(noise(d), 600) * exp_env(n, 12) * 0.6
    return x


def death():
    d = 0.6
    n = int(SR * d)
    thud = sine(lambda tt: 90 * np.exp(-tt * 4) + 40, d) * exp_env(n, 8)
    dust = lp(noise(d), 800) * exp_env(n, 10) * 0.5
    return mix(thud, dust)


def creep_die():
    d = 0.35
    n = int(SR * d)
    sq = sine(lambda tt: 700 - 1400 * tt, d) * exp_env(n, 12) * 0.5
    thud = lp(noise(d), 300) * exp_env(n, 20)
    return mix(sq, thud)


def level_up():
    d = 1.0
    n = int(SR * d)
    x = np.zeros(n)
    for k, f in enumerate([523, 659, 784, 1046]):
        st = int(k * 0.09 * SR)
        tone = (sine(f, n - st) + 0.3 * sine(f * 2, n - st)) * exp_env(n - st, 4)
        x[st:] += tone * 0.5
    return x


def coin():
    d = 0.3
    n = int(SR * d)
    return sine(1900, d) * exp_env(n, 14) + np.pad(sine(2500, n - int(0.06 * SR)) * exp_env(n - int(0.06 * SR), 12), (int(0.06 * SR), 0))


def buy():
    d = 0.5
    n = int(SR * d)
    return mix(coin(), np.pad(coin() * 0.7, (int(0.08 * SR), 0)), lp(noise(d), 1500) * exp_env(n, 25) * 0.3)


def potion():
    d = 0.6
    n = int(SR * d)
    gulp = np.zeros(n)
    for k in range(3):
        st = int(k * 0.15 * SR)
        g = sine(lambda tt: 300 + 400 * tt, 0.1) * exp_env(int(0.1 * SR), 25)
        gulp[st:st + len(g)] += g
    sparkle = hp(noise(d), 5000) * env(n, 0.2, 0.2, 0.1, 0.2) * 0.3
    return mix(gulp, sparkle)


def ui_click():
    d = 0.06
    n = int(SR * d)
    return sine(1200, d) * exp_env(n, 80)


def ui_error():
    d = 0.25
    n = int(SR * d)
    return (sine(180, d) + 0.5 * sine(190, d)) * env(n, 0.005, 0.05, 0.6, 0.08)


def victory():
    d = 2.2
    n = int(SR * d)
    x = np.zeros(n)
    for k, f in enumerate([392, 523, 659, 784, 1046]):
        st = int(k * 0.12 * SR)
        tone = (sine(f, n - st) + 0.4 * sine(f * 2, n - st) + 0.2 * sine(f * 3, n - st)) * exp_env(n - st, 1.8)
        x[st:] += tone * 0.4
    return x


def defeat():
    d = 2.4
    n = int(SR * d)
    x = np.zeros(n)
    for k, f in enumerate([392, 349, 311, 262]):
        st = int(k * 0.3 * SR)
        tone = (sine(f, n - st) + 0.3 * sine(f * 2, n - st)) * exp_env(n - st, 1.5)
        x[st:] += tone * 0.4
    return lp(x, 2500)


for fn in [swing, hit, slash_heavy, blink, ice_cast, ice_shatter, freeze, buff_up, transform, time_stop, time_resume,
           mugetsu, poison, wave_horn, boss_roar, crystal_hit, crystal_break, portal, duel_gong, death, creep_die,
           level_up, coin, buy, potion, ui_click, ui_error, victory, defeat]:
    save(fn.__name__, fn())

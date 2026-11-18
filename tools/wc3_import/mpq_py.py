"""Чтение MPQ (Warcraft 3) без внешних библиотек: zlib, PKWare DCL (implode), шифрование."""
import struct
import zlib
import bz2

M = 0xFFFFFFFF
CRYPT = [0] * 0x500
_seed = 0x00100001
for _i1 in range(0x100):
    _i2 = _i1
    for _ in range(5):
        _seed = (_seed * 125 + 3) % 0x2AAAAB
        _t1 = (_seed & 0xFFFF) << 0x10
        _seed = (_seed * 125 + 3) % 0x2AAAAB
        _t2 = _seed & 0xFFFF
        CRYPT[_i2] = _t1 | _t2
        _i2 += 0x100


def hash_string(s, t):
    s1, s2 = 0x7FED7FED, 0xEEEEEEEE
    for ch in s.upper().replace('/', '\\').encode('latin1'):
        s1 = CRYPT[(t << 8) + ch] ^ ((s1 + s2) & M)
        s2 = (ch + s1 + s2 + (s2 << 5) + 3) & M
    return s1


def decrypt(words, key):
    seed = 0xEEEEEEEE
    out = []
    for w in words:
        seed = (seed + CRYPT[0x400 + (key & 0xFF)]) & M
        ch = w ^ ((key + seed) & M)
        out.append(ch)
        key = ((((~key) & M) << 0x15) + 0x11111111 | (key >> 0x0B)) & M
        seed = (ch + seed + (seed << 5) + 3) & M
    return out


def decrypt_bytes(b, key):
    n = len(b) // 4
    w = decrypt(struct.unpack('<%dI' % n, b[:n * 4]), key)
    return struct.pack('<%dI' % n, *w) + b[n * 4:]


# ---------------------------------------------------------------- PKWare DCL explode (по blast.c)
LITLEN = [11, 124, 8, 7, 28, 7, 188, 13, 76, 4, 10, 8, 12, 10, 12, 10, 8, 23, 8, 9, 7, 6, 7, 8, 7, 6, 55, 8, 23, 24,
          12, 11, 7, 9, 11, 12, 6, 7, 22, 5, 7, 24, 6, 11, 9, 6, 7, 22, 7, 11, 38, 7, 9, 8, 25, 11, 8, 11, 9, 12, 8,
          12, 5, 38, 5, 38, 5, 11, 7, 5, 6, 21, 6, 10, 53, 8, 7, 24, 10, 27, 44, 253, 253, 253, 252, 252, 252, 13, 12,
          45, 12, 45, 12, 61, 12, 45, 44, 173]
LENLEN = [2, 35, 36, 53, 38, 23]
DISTLEN = [2, 20, 53, 230, 247, 151, 248]
BASE = [3, 2, 4, 5, 6, 7, 8, 9, 10, 12, 16, 24, 40, 72, 136, 264]
EXTRA = [0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8]


def _construct(rep):
    length = []
    for b in rep:
        n = (b >> 4) + 1
        length += [b & 15] * n
    count = [0] * 14
    for l in length:
        count[l] += 1
    offs = [0] * 14
    for l in range(1, 13):
        offs[l + 1] = offs[l] + count[l]
    sym = [0] * len(length)
    for s, l in enumerate(length):
        if l:
            sym[offs[l]] = s
            offs[l] += 1
    return count, sym


LITCODE = _construct(LITLEN)
LENCODE = _construct(LENLEN)
DISTCODE = _construct(DISTLEN)


def explode(data):
    pos = [0]
    bitbuf = [0]
    bitcnt = [0]

    def bits(n):
        v = bitbuf[0]
        while bitcnt[0] < n:
            v |= data[pos[0]] << bitcnt[0]
            pos[0] += 1
            bitcnt[0] += 8
        bitbuf[0] = v >> n
        bitcnt[0] -= n
        return v & ((1 << n) - 1)

    def decode(h):
        count, sym = h
        code = first = index = 0
        for ln in range(1, 14):
            code |= bits(1) ^ 1
            c = count[ln]
            if code < first + c:
                return sym[index + (code - first)]
            index += c
            first += c
            first <<= 1
            code <<= 1
        raise ValueError('bad code')

    lit = bits(8)
    dct = bits(8)
    out = bytearray()
    while True:
        if bits(1):
            s = decode(LENCODE)
            ln = BASE[s] + bits(EXTRA[s])
            if ln == 519:
                break
            sb = 2 if ln == 2 else dct
            dist = (decode(DISTCODE) << sb) + bits(sb) + 1
            st = len(out) - dist
            for k in range(ln):
                out.append(out[st + k])
        else:
            out.append(decode(LITCODE) if lit else bits(8))
    return bytes(out)


def decompress_sector(b, expected, multi):
    if not multi:
        return explode(b)
    mask = b[0]
    d = b[1:]
    if mask & 0x10:
        d = bz2.decompress(d)
    if mask & 0x08:
        d = explode(d)
    if mask & 0x02:
        d = zlib.decompress(d)
    if mask & ~0x1A:
        raise NotImplementedError('compression %02x' % mask)
    return d


class Archive:
    def __init__(self, path):
        self.f = open(path, 'rb')
        self.base = 0
        while True:
            self.f.seek(self.base)
            if self.f.read(4) == b'MPQ\x1a':
                break
            self.base += 512
        self.f.seek(self.base)
        h = self.f.read(32)
        (_, hsize, asize, ver, sshift, htpos, btpos, hn, bn) = struct.unpack('<4sIIHHIIII', h)
        self.sector = 512 << sshift
        self.f.seek(self.base + htpos)
        ht = decrypt(struct.unpack('<%dI' % (hn * 4), self.f.read(hn * 16)), hash_string('(hash table)', 3))
        self.hash = [ht[i * 4:i * 4 + 4] for i in range(hn)]
        self.f.seek(self.base + btpos)
        bt = decrypt(struct.unpack('<%dI' % (bn * 4), self.f.read(bn * 16)), hash_string('(block table)', 3))
        self.block = [bt[i * 4:i * 4 + 4] for i in range(bn)]

    def find(self, name):
        n = len(self.hash)
        i = hash_string(name, 0) & (n - 1)
        a, b = hash_string(name, 1), hash_string(name, 2)
        for _ in range(n):
            e = self.hash[i]
            if e[3] == 0xFFFFFFFF:
                return None
            if e[0] == a and e[1] == b and e[3] != 0xFFFFFFFE:
                return self.block[e[3]]
            i = (i + 1) & (n - 1)
        return None

    def read(self, name):
        blk = self.find(name)
        if blk is None:
            return None
        pos, csize, fsize, flags = blk
        if not flags & 0x80000000:
            return None
        self.f.seek(self.base + pos)
        raw = self.f.read(csize)
        key = 0
        if flags & 0x10000:
            key = hash_string(name.replace('/', '\\').split('\\')[-1], 3)
            if flags & 0x20000:
                key = ((key + pos) ^ fsize) & M
        comp = flags & 0x300
        if flags & 0x01000000:  # single unit
            if key:
                raw = decrypt_bytes(raw, key)
            if comp and csize < fsize:
                return decompress_sector(raw, fsize, bool(flags & 0x200))
            return raw
        if not comp:
            if key:
                out = bytearray()
                for s in range(0, len(raw), self.sector):
                    out += decrypt_bytes(raw[s:s + self.sector], (key + s // self.sector) & M)
                return bytes(out)
            return raw
        ns = (fsize + self.sector - 1) // self.sector
        tbl = list(struct.unpack('<%dI' % (ns + 1), raw[:(ns + 1) * 4]))
        if key:
            tbl = decrypt(tbl, (key - 1) & M)
        out = bytearray()
        for s in range(ns):
            chunk = raw[tbl[s]:tbl[s + 1]]
            if key:
                chunk = decrypt_bytes(chunk, (key + s) & M)
            want = min(self.sector, fsize - s * self.sector)
            if len(chunk) < want:
                chunk = decompress_sector(chunk, want, bool(flags & 0x200))
            out += chunk
        return bytes(out)

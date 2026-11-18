extends SceneTree
## Извлекает из архивов Warcraft 3 (war3.mpq, War3x.mpq, ...) только нужные файлы: модели эффектов и их текстуры.
## Запуск: ИЗВЛЕЧЬ_ЭФФЕКТЫ.bat (через Godot из папки проекта, ничего ставить не нужно).

const M := 0xFFFFFFFF
var crypt := PackedInt64Array()
var log_lines: PackedStringArray = []


class Archive:
	var f: FileAccess
	var base := 0
	var sector := 4096
	var hash_tbl := PackedInt64Array()
	var block_tbl := PackedInt64Array()
	var nhash := 0
	var name := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		print("usage: -- <папка Warcraft 3> <куда> <список.txt>")
		quit(1)
		return
	_build_crypt()
	var war3: String = args[0]
	var out_dir: String = args[1]
	var list: PackedStringArray = FileAccess.get_file_as_string(args[2]).split("\n", false)
	var archives: Array = []
	for n in ["War3Patch.mpq", "War3xlocal.mpq", "War3x.mpq", "war3.mpq", "War3Local.mpq"]:
		var p := war3.path_join(n)
		if FileAccess.file_exists(p):
			var a := _open(p)
			if a:
				archives.append(a)
				print("Открыт архив: ", n)
	if archives.is_empty():
		print("Не найдены архивы Warcraft 3 в ", war3)
		quit(1)
		return
	var queue: Array = []
	var patterns: Array = []
	for l in list:
		var s := l.strip_edges()
		if s == "":
			continue
		if "*" in s:
			patterns.append(s.to_lower().replace("/", "\\"))
		else:
			queue.append(s)
	if not patterns.is_empty():
		# шаблоны вида Abilities\Spells\*.mdx — по списку файлов архивов
		for a in archives:
			var lf: Variant = _read(a, "(listfile)")
			if lf == null:
				continue
			for n in (lf as PackedByteArray).get_string_from_ascii().split("\n", false):
				var nn := n.strip_edges()
				for p in patterns:
					if nn.to_lower().matchn(p):
						queue.append(nn)
						break
		print("По шаблонам найдено файлов: ", queue.size())
	var done := {}
	var ok := 0
	var missing := 0
	while not queue.is_empty():
		var path: String = queue.pop_front()
		var key := path.to_upper().replace("/", "\\")
		if done.has(key):
			continue
		done[key] = true
		var data := PackedByteArray()
		var found := false
		for a in archives:
			var r: Variant = _read(a, path)
			if r != null:
				data = r
				found = true
				break
		if not found:
			missing += 1
			log_lines.append("нет: " + path)
			continue
		_pack_add(out_dir, path, data)
		ok += 1
		if path.to_lower().ends_with(".mdx"):
			for t in _mdx_textures(data):
				queue.append(t)
		if ok % 50 == 0:
			print("  извлечено файлов: ", ok)
	if pack:
		pack.close()
	var lf := FileAccess.open(out_dir.path_join("extract_log.txt"), FileAccess.WRITE)
	if lf:
		lf.store_string("извлечено: %d, не найдено: %d\n%s\n" % [ok, missing, "\n".join(log_lines)])
	print("Готово: извлечено %d файлов, не найдено %d. Папка: %s" % [ok, missing, out_dir])
	quit(0)


# ----------------------------------------------------------------- пакеты по ~30 МБ: [u16 длина пути][путь][u32 размер][данные]
var pack: FileAccess = null
var pack_n := 0


func _pack_add(out_dir: String, path: String, data: PackedByteArray) -> void:
	if pack == null or pack.get_position() + data.size() > 30_000_000:
		if pack:
			pack.close()
		pack_n += 1
		DirAccess.make_dir_recursive_absolute(out_dir)
		pack = FileAccess.open(out_dir.path_join("war3_assets_%02d.pak" % pack_n), FileAccess.WRITE)
	var p := path.to_utf8_buffer()
	pack.store_16(p.size())
	pack.store_buffer(p)
	pack.store_32(data.size())
	pack.store_buffer(data)


# ----------------------------------------------------------------- шифрование MPQ
func _build_crypt() -> void:
	crypt.resize(0x500)
	var seed := 0x00100001
	for i1 in 0x100:
		var i2 := i1
		for k in 5:
			seed = (seed * 125 + 3) % 0x2AAAAB
			var t1 := (seed & 0xFFFF) << 0x10
			seed = (seed * 125 + 3) % 0x2AAAAB
			var t2 := seed & 0xFFFF
			crypt[i2] = t1 | t2
			i2 += 0x100


func _hash(s: String, t: int) -> int:
	var s1 := 0x7FED7FED
	var s2 := 0xEEEEEEEE
	var b := s.to_upper().replace("/", "\\").to_ascii_buffer()
	for ch in b:
		s1 = (crypt[(t << 8) + ch] ^ ((s1 + s2) & M)) & M
		s2 = (ch + s1 + s2 + (s2 << 5) + 3) & M
	return s1


func _decrypt_words(words: PackedInt64Array, key: int) -> PackedInt64Array:
	var seed := 0xEEEEEEEE
	for i in words.size():
		seed = (seed + crypt[0x400 + (key & 0xFF)]) & M
		var ch := (words[i] ^ ((key + seed) & M)) & M
		words[i] = ch
		key = (((((~key) & M) << 0x15) + 0x11111111) | (key >> 0x0B)) & M
		seed = (ch + seed + (seed << 5) + 3) & M
	return words


func _words(b: PackedByteArray) -> PackedInt64Array:
	var n := b.size() / 4
	var w := PackedInt64Array()
	w.resize(n)
	for i in n:
		w[i] = b.decode_u32(i * 4)
	return w


func _bytes(w: PackedInt64Array, tail: PackedByteArray) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(w.size() * 4)
	for i in w.size():
		b.encode_u32(i * 4, w[i])
	b.append_array(tail)
	return b


func _decrypt_bytes(b: PackedByteArray, key: int) -> PackedByteArray:
	var n := b.size() / 4
	return _bytes(_decrypt_words(_words(b.slice(0, n * 4)), key), b.slice(n * 4))


# ----------------------------------------------------------------- архив
func _open(path: String) -> Archive:
	var a := Archive.new()
	a.name = path
	a.f = FileAccess.open(path, FileAccess.READ)
	if a.f == null:
		return null
	a.base = 0
	while true:
		if a.base >= a.f.get_length():
			return null
		a.f.seek(a.base)
		if a.f.get_buffer(4) == PackedByteArray([0x4D, 0x50, 0x51, 0x1A]):
			break
		a.base += 512
	a.f.seek(a.base + 4)
	var h := a.f.get_buffer(28)
	var sshift := h.decode_u16(10)
	var htpos := h.decode_u32(12)
	var btpos := h.decode_u32(16)
	var hn := h.decode_u32(20)
	var bn := h.decode_u32(24)
	a.sector = 512 << sshift
	a.f.seek(a.base + htpos)
	a.hash_tbl = _decrypt_words(_words(a.f.get_buffer(hn * 16)), _hash("(hash table)", 3))
	a.f.seek(a.base + btpos)
	a.block_tbl = _decrypt_words(_words(a.f.get_buffer(bn * 16)), _hash("(block table)", 3))
	a.nhash = hn
	return a


func _find(a: Archive, name: String) -> int:
	var n := a.nhash
	var i := _hash(name, 0) & (n - 1)
	var h1 := _hash(name, 1)
	var h2 := _hash(name, 2)
	for k in n:
		var bi := a.hash_tbl[i * 4 + 3]
		if bi == 0xFFFFFFFF:
			return -1
		if a.hash_tbl[i * 4] == h1 and a.hash_tbl[i * 4 + 1] == h2 and bi != 0xFFFFFFFE:
			return bi
		i = (i + 1) & (n - 1)
	return -1


func _read(a: Archive, name: String) -> Variant:
	var bi := _find(a, name)
	if bi < 0:
		return null
	var pos := a.block_tbl[bi * 4]
	var csize := a.block_tbl[bi * 4 + 1]
	var fsize := a.block_tbl[bi * 4 + 2]
	var flags := a.block_tbl[bi * 4 + 3]
	if not (flags & 0x80000000):
		return null
	a.f.seek(a.base + pos)
	var raw := a.f.get_buffer(csize)
	var key := 0
	if flags & 0x10000:
		key = _hash(name.replace("/", "\\").get_file().split("\\")[-1], 3)
		if flags & 0x20000:
			key = ((key + pos) ^ fsize) & M
	var comp := flags & 0x300
	var multi := (flags & 0x200) != 0
	if flags & 0x01000000:
		if key:
			raw = _decrypt_bytes(raw, key)
		if comp and csize < fsize:
			return _decompress(raw, fsize, multi)
		return raw
	if not comp:
		if key:
			var o := PackedByteArray()
			var s := 0
			while s < raw.size():
				o.append_array(_decrypt_bytes(raw.slice(s, s + a.sector), (key + s / a.sector) & M))
				s += a.sector
			return o
		return raw
	var ns := (fsize + a.sector - 1) / a.sector
	var tbl := _words(raw.slice(0, (ns + 1) * 4))
	if key:
		tbl = _decrypt_words(tbl, (key - 1) & M)
	var out := PackedByteArray()
	for s in ns:
		var chunk := raw.slice(tbl[s], tbl[s + 1])
		if key:
			chunk = _decrypt_bytes(chunk, (key + s) & M)
		var want := mini(a.sector, fsize - s * a.sector)
		if chunk.size() < want:
			var d: Variant = _decompress(chunk, want, multi)
			if d == null:
				log_lines.append("не распаковать (метод сжатия): " + name)
				return null
			chunk = d
		out.append_array(chunk)
	return out


func _decompress(b: PackedByteArray, want: int, multi: bool) -> Variant:
	if not multi:
		return _explode(b)
	var mask := b[0]
	var d := b.slice(1)
	if mask & ~0x0A:
		return null  # bzip2 / ADPCM / Huffman (звуки) не нужны
	if mask & 0x08:
		d = _explode(d)
	if mask & 0x02:
		d = d.decompress(want, FileAccess.COMPRESSION_DEFLATE)
	return d


# ----------------------------------------------------------------- PKWare DCL (по blast.c)
const LITLEN := [11, 124, 8, 7, 28, 7, 188, 13, 76, 4, 10, 8, 12, 10, 12, 10, 8, 23, 8, 9, 7, 6, 7, 8, 7, 6, 55, 8, 23, 24,
	12, 11, 7, 9, 11, 12, 6, 7, 22, 5, 7, 24, 6, 11, 9, 6, 7, 22, 7, 11, 38, 7, 9, 8, 25, 11, 8, 11, 9, 12, 8,
	12, 5, 38, 5, 38, 5, 11, 7, 5, 6, 21, 6, 10, 53, 8, 7, 24, 10, 27, 44, 253, 253, 253, 252, 252, 252, 13, 12,
	45, 12, 45, 12, 61, 12, 45, 44, 173]
const LENLEN := [2, 35, 36, 53, 38, 23]
const DISTLEN := [2, 20, 53, 230, 247, 151, 248]
const BASE := [3, 2, 4, 5, 6, 7, 8, 9, 10, 12, 16, 24, 40, 72, 136, 264]
const EXTRA := [0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8]
var _codes := {}
var _in := PackedByteArray()
var _pos := 0
var _bitbuf := 0
var _bitcnt := 0


func _construct(rep: Array) -> Array:
	var length: Array = []
	for b in rep:
		for k in (b >> 4) + 1:
			length.append(b & 15)
	var count: Array = []
	count.resize(14)
	count.fill(0)
	for l in length:
		count[l] += 1
	var offs: Array = []
	offs.resize(14)
	offs.fill(0)
	for l in range(1, 13):
		offs[l + 1] = offs[l] + count[l]
	var sym: Array = []
	sym.resize(length.size())
	sym.fill(0)
	for s in length.size():
		var l: int = length[s]
		if l:
			sym[offs[l]] = s
			offs[l] += 1
	return [count, sym]


func _bits(n: int) -> int:
	var v := _bitbuf
	while _bitcnt < n:
		v |= _in[_pos] << _bitcnt
		_pos += 1
		_bitcnt += 8
	_bitbuf = v >> n
	_bitcnt -= n
	return v & ((1 << n) - 1)


func _decode(h: Array) -> int:
	var count: Array = h[0]
	var sym: Array = h[1]
	var code := 0
	var first := 0
	var index := 0
	for ln in range(1, 14):
		code |= _bits(1) ^ 1
		var c: int = count[ln]
		if code < first + c:
			return sym[index + (code - first)]
		index += c
		first += c
		first <<= 1
		code <<= 1
	return -1


func _explode(data: PackedByteArray) -> PackedByteArray:
	if _codes.is_empty():
		_codes = {"lit": _construct(LITLEN), "len": _construct(LENLEN), "dist": _construct(DISTLEN)}
	_in = data
	_pos = 0
	_bitbuf = 0
	_bitcnt = 0
	var lit := _bits(8)
	var dct := _bits(8)
	var out := PackedByteArray()
	while true:
		if _bits(1):
			var s := _decode(_codes["len"])
			var ln: int = BASE[s] + _bits(EXTRA[s])
			if ln == 519:
				break
			var sb: int = 2 if ln == 2 else dct
			var dist := (_decode(_codes["dist"]) << sb) + _bits(sb) + 1
			var st := out.size() - dist
			for k in ln:
				out.append(out[st + k])
		else:
			out.append(_decode(_codes["lit"]) if lit else _bits(8))
	return out


# ----------------------------------------------------------------- текстуры модели
func _mdx_textures(d: PackedByteArray) -> PackedStringArray:
	var out := PackedStringArray()
	if d.size() < 8 or d.slice(0, 4).get_string_from_ascii() != "MDLX":
		return out
	var p := 4
	while p + 8 <= d.size():
		var tag := d.slice(p, p + 4).get_string_from_ascii()
		var size := d.decode_u32(p + 4)
		if tag == "TEXS":
			var q := p + 8
			while q + 268 <= p + 8 + size:
				var path := d.slice(q + 4, q + 264).get_string_from_ascii()
				if path != "":
					out.append(path)
				q += 268
		p += 8 + size
	return out

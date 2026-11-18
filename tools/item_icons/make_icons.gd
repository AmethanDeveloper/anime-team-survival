extends SceneTree
## Иконки предметов из архивов Warcraft 3 (war3.mpq, War3x.mpq): часть иконок карты ATS — стандартные иконки WC3,
## их нет в файле карты, поэтому они берутся из установленной игры на этом компьютере.
## Запуск (это делает установщик обновления):
##   Godot --headless --path tools/item_icons -- "<папка Warcraft 3>" "<папка game>"
## Проверка декодера: Godot --headless --path tools/item_icons -- --blp <файл.blp> <файл.png>
## Готовые картинки: game/items/icons/<id>.png (64×64). Уже существующие файлы не перезаписываются.

const M := 0xFFFFFFFF
var crypt := PackedInt64Array()
var log_lines: PackedStringArray = []

## id предмета -> пути иконки в архивах (берётся первый найденный)
const ICONS := {
	"ancestral_spear": ["ReplaceableTextures\\CommandButtons\\BTNNagaWeaponUp3.blp"],
	"antimagic": ["ReplaceableTextures\\PassiveButtons\\PASBTNRegenerationAura.blp", "ReplaceableTextures\\CommandButtons\\BTNRegenerationAura.blp"],
	"black_sword": ["ReplaceableTextures\\CommandButtons\\BTNArcaniteMelee.blp"],
	"blade_sin": ["ReplaceableTextures\\CommandButtons\\BTNUpgradeMoonGlaive.blp"],
	"blood_diamond": ["ReplaceableTextures\\CommandButtons\\BTNPhilosophersStone.blp"],
	"chakra_stick": ["ReplaceableTextures\\CommandButtons\\BTNWandOfManaSteal.blp"],
	"claws_chaos": ["ReplaceableTextures\\CommandButtons\\BTNShamanMaster.blp"],
	"dark_glove": ["ReplaceableTextures\\CommandButtons\\BTNImprovedUnholyStrength.blp"],
	"dark_keyblade": ["ReplaceableTextures\\CommandButtons\\BTNGhostKey.blp"],
	"dragon_shield": ["ReplaceableTextures\\CommandButtons\\BTNArcaniteArmor.blp"],
	"dragon_skin": ["ReplaceableTextures\\CommandButtons\\BTNAdvancedReinforcedHides.blp"],
	"elixir_health": ["ReplaceableTextures\\CommandButtons\\BTNShimmerWeed.blp"],
	"elixir_invuln": ["ReplaceableTextures\\CommandButtons\\BTNWellSpring.blp"],
	"elven_mail": ["ReplaceableTextures\\CommandButtons\\BTNAdvancedMoonArmor.blp"],
	"emerald_ring": ["ReplaceableTextures\\CommandButtons\\BTNRingJadeFalcon.blp"],
	"feather_flame": ["ReplaceableTextures\\CommandButtons\\BTNStaffOfSanctuary.blp"],
	"glove_demonic": ["ReplaceableTextures\\CommandButtons\\BTNAdvancedUnholyStrength.blp"],
	"glove_speed": ["ReplaceableTextures\\CommandButtons\\BTNGlove.blp"],
	"gold_amulet": ["ReplaceableTextures\\CommandButtons\\BTNAmulet.blp"],
	"health_staff": ["ReplaceableTextures\\CommandButtons\\BTNPriestMaster.blp"],
	"health_stone": ["ReplaceableTextures\\CommandButtons\\BTNPeriapt1.blp"],
	"key_set": ["ReplaceableTextures\\CommandButtons\\BTNMoonKey.blp"],
	"leaf_ygg": ["ReplaceableTextures\\CommandButtons\\BTNEntanglingRoots.blp"],
	"light_keyblade": ["ReplaceableTextures\\CommandButtons\\BTNBloodKey.blp"],
	"lightning_sword": ["ReplaceableTextures\\CommandButtons\\BTNThoriumMelee.blp"],
	"lumber_shield": ["ReplaceableTextures\\CommandButtons\\BTNDefendStop.blp"],
	"lumber_sword": ["ReplaceableTextures\\CommandButtons\\BTNAlleriaFlute.blp"],
	"moon_ring": ["ReplaceableTextures\\CommandButtons\\BTNRingSkull.blp"],
	"rainbow_ring": ["ReplaceableTextures\\CommandButtons\\BTNGoldRing.blp"],
	"recipe_element": ["ReplaceableTextures\\CommandButtons\\BTN3M3.blp"],
	"remains": ["ReplaceableTextures\\CommandButtons\\BTNSpellSteal.blp"],
	"resist_skin": ["ReplaceableTextures\\CommandButtons\\BTNResistantSkin.blp"],
	"ring_regen": ["ReplaceableTextures\\CommandButtons\\BTNRingSkull.blp"],
	"ruby_ring": ["ReplaceableTextures\\CommandButtons\\BTNRingLionHead.blp"],
	"sapphire_ring": ["ReplaceableTextures\\CommandButtons\\BTNRingVioletSpider.blp"],
	"short_sword": ["ReplaceableTextures\\CommandButtons\\BTNSteelMelee.blp"],
	"soul_nature": ["ReplaceableTextures\\CommandButtons\\BTNRegenerate.blp"],
	"spirit_claw": ["ReplaceableTextures\\CommandButtons\\BTNCreatureAttack.blp"],
	"studded_armor": ["ReplaceableTextures\\CommandButtons\\BTNLeatherUpgradeOne.blp"],
	"tome_agi": ["ReplaceableTextures\\CommandButtons\\BTNTomeGreen.blp", "ReplaceableTextures\\CommandButtons\\BTNTome.blp"],
	"tome_all": ["ReplaceableTextures\\CommandButtons\\BTNTome.blp"],
	"tome_combat": ["ReplaceableTextures\\CommandButtons\\BTNSorceressAdept.blp", "ReplaceableTextures\\CommandButtons\\BTNTome.blp"],
	"tome_exp": ["ReplaceableTextures\\CommandButtons\\BTNTomeBrown.blp", "ReplaceableTextures\\CommandButtons\\BTNTome.blp"],
	"tome_int": ["ReplaceableTextures\\CommandButtons\\BTNTomeBlue.blp", "ReplaceableTextures\\CommandButtons\\BTNTome.blp"],
	"tome_str": ["ReplaceableTextures\\CommandButtons\\BTNTomeRed.blp", "ReplaceableTextures\\CommandButtons\\BTNTome.blp"],
	"unknown_bone": ["ReplaceableTextures\\CommandButtons\\BTNTentacle.blp"],
	"unknown_item": ["ReplaceableTextures\\CommandButtons\\BTNAdvancedStrengthOfTheWild.blp"],
	"vamp_potion": ["ReplaceableTextures\\CommandButtons\\BTNPotionOfVampirism.blp"],
	"water_shield": ["ReplaceableTextures\\CommandButtons\\BTNFrostArmor.blp"],
	"wind_break": ["ReplaceableTextures\\CommandButtons\\BTNHeartOfSearinox.blp"],
	"x_keyblade": ["ReplaceableTextures\\CommandButtons\\BTNBlood&GhostKey.blp"],
}


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
	_build_crypt()
	_build_cos()
	if args.size() >= 3 and args[0] == "--blp":
		var img := blp_to_image(FileAccess.get_file_as_bytes(args[1]))
		if img == null:
			print("не удалось прочитать ", args[1])
			quit(1)
			return
		img.save_png(args[2])
		print("ok ", img.get_size())
		quit(0)
		return
	if args.size() < 2:
		print("usage: -- <папка Warcraft 3> <папка game>")
		quit(1)
		return
	var war3: String = args[0]
	var out_dir: String = args[1].path_join("items").path_join("icons")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var archives: Array = []
	for n in ["War3Patch.mpq", "War3xlocal.mpq", "War3x.mpq", "war3.mpq", "War3Local.mpq"]:
		var p := war3.path_join(n)
		if FileAccess.file_exists(p):
			var a := _open(p)
			if a:
				archives.append(a)
	if archives.is_empty():
		print("Иконки предметов: не найдены архивы Warcraft 3 в ", war3, " — останутся рисованные иконки")
		quit(0)
		return
	var ok := 0
	var skip := 0
	var miss: PackedStringArray = []
	for id in ICONS:
		var dst := out_dir.path_join(id + ".png")
		if FileAccess.file_exists(dst):
			skip += 1
			continue
		var img: Image = null
		for path in ICONS[id]:
			for a in archives:
				var r: Variant = _read(a, path)
				if r != null:
					img = blp_to_image(r)
					if img:
						break
			if img:
				break
		if img == null:
			miss.append(id)
			continue
		if img.get_width() != 64 or img.get_height() != 64:
			img.resize(64, 64, Image.INTERPOLATE_LANCZOS)
		img.save_png(dst)
		ok += 1
	print("Иконки предметов из Warcraft 3: готово %d, уже были %d, не найдено %d %s" % [ok, skip, miss.size(), ", ".join(miss)])
	quit(0)


# ----------------------------------------------------------------- BLP1: JPEG (4 канала BGRA) и палитра
## Godot не читает JPEG с четырьмя каналами, поэтому здесь свой небольшой декодер baseline JPEG.
func blp_to_image(b: PackedByteArray) -> Image:
	if b.size() < 160 or b.slice(0, 4).get_string_from_ascii() != "BLP1":
		return null
	var comp := b.decode_u32(4)
	var w := b.decode_u32(12)
	var h := b.decode_u32(16)
	var off0 := b.decode_u32(28)
	var len0 := b.decode_u32(92)
	if w <= 0 or h <= 0 or w > 1024 or h > 1024:
		return null
	var px := PackedByteArray()
	px.resize(w * h * 3)
	if comp == 0:
		var hs := b.decode_u32(156)
		var jpg := b.slice(160, 160 + hs)
		jpg.append_array(b.slice(off0, off0 + len0))
		var j := jpeg_decode(jpg)
		if j.is_empty() or int(j.w) < w or int(j.h) < h:
			return null
		var nc: int = (j.planes as Array).size()
		for y in h:
			for x in w:
				var o := (y * w + x) * 3
				px[o] = _sample(j, 2 if nc > 2 else 0, x, y)
				px[o + 1] = _sample(j, 1 if nc > 1 else 0, x, y)
				px[o + 2] = _sample(j, 0, x, y)
	else:
		var pal := b.slice(156, 156 + 1024)
		for i in w * h:
			var k := b[off0 + i] if off0 + i < b.size() else 0
			px[i * 3] = pal[k * 4 + 2]
			px[i * 3 + 1] = pal[k * 4 + 1]
			px[i * 3 + 2] = pal[k * 4]
	return Image.create_from_data(w, h, false, Image.FORMAT_RGB8, px)


func _sample(j: Dictionary, c: int, x: int, y: int) -> int:
	var cc: Dictionary = j.comps[c]
	var sx := x * int(cc.h) / int(j.hmax)
	var sy := y * int(cc.v) / int(j.vmax)
	return (j.planes[c] as PackedByteArray)[sy * int(cc.pw) + sx]


const ZZ := [0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21,
	28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63]
var _cos := PackedFloat32Array()
var _d := PackedByteArray()
var _p := 0
var _bb := 0
var _bc := 0


func _build_cos() -> void:
	_cos.resize(64)
	for x in 8:
		for u in 8:
			var cu := 1.0 / sqrt(2.0) if u == 0 else 1.0
			_cos[x * 8 + u] = cu * cos((2.0 * x + 1.0) * u * PI / 16.0) / 2.0


func jpeg_decode(d: PackedByteArray) -> Dictionary:
	if d.size() < 4 or d[0] != 0xFF or d[1] != 0xD8:
		return {}
	var qt := [PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	var hts := {}
	var comps: Array = []
	var res := {}
	var ri := 0
	var p := 2
	while p + 3 < d.size():
		if d[p] != 0xFF:
			p += 1
			continue
		var mk := d[p + 1]
		if mk == 0xFF:
			p += 1
			continue
		p += 2
		if mk == 0xD8 or mk == 0x01 or (mk >= 0xD0 and mk <= 0xD7):
			continue
		if mk == 0xD9:
			break
		var ln := (d[p] << 8) | d[p + 1]
		var seg_end := p + ln
		if mk == 0xDB:
			var q := p + 2
			while q < seg_end:
				var pq := d[q] >> 4
				var tq := d[q] & 15
				q += 1
				var t := PackedInt32Array()
				t.resize(64)
				for i in 64:
					if pq == 0:
						t[i] = d[q]
						q += 1
					else:
						t[i] = (d[q] << 8) | d[q + 1]
						q += 2
				qt[tq & 3] = t
		elif mk == 0xC0 or mk == 0xC1:
			res.h = (d[p + 3] << 8) | d[p + 4]
			res.w = (d[p + 5] << 8) | d[p + 6]
			var nc := d[p + 7]
			comps.clear()
			var hmax := 1
			var vmax := 1
			for c in nc:
				var o := p + 8 + c * 3
				var cc := {"id": d[o], "h": maxi(1, d[o + 1] >> 4), "v": maxi(1, d[o + 1] & 15), "tq": d[o + 2] & 3, "pred": 0,
					"td": 0, "ta": 0}
				hmax = maxi(hmax, cc.h)
				vmax = maxi(vmax, cc.v)
				comps.append(cc)
			res.hmax = hmax
			res.vmax = vmax
			var mcux := int(ceil(float(res.w) / (8.0 * hmax)))
			var mcuy := int(ceil(float(res.h) / (8.0 * vmax)))
			res.mcux = mcux
			res.mcuy = mcuy
			var planes: Array = []
			for cc in comps:
				cc.pw = mcux * int(cc.h) * 8
				cc.ph = mcuy * int(cc.v) * 8
				var pb := PackedByteArray()
				pb.resize(int(cc.pw) * int(cc.ph))
				planes.append(pb)
			res.comps = comps
			res.planes = planes
		elif mk == 0xC2 or mk == 0xC3 or (mk >= 0xC5 and mk <= 0xCF and mk != 0xC8 and mk != 0xCC):
			return {}  # прогрессивный и прочие режимы — у иконок WC3 их нет
		elif mk == 0xC4:
			var q2 := p + 2
			while q2 < seg_end:
				var tc := d[q2] >> 4
				var th := d[q2] & 15
				var counts := d.slice(q2 + 1, q2 + 17)
				var n := 0
				for c2 in counts:
					n += c2
				var syms := d.slice(q2 + 17, q2 + 17 + n)
				hts[tc * 16 + th] = _huff(counts, syms)
				q2 += 17 + n
		elif mk == 0xDD:
			ri = (d[p + 2] << 8) | d[p + 3]
		elif mk == 0xDA:
			if comps.is_empty():
				return {}
			var ns := d[p + 2]
			var sc: Array = []
			for k in ns:
				var cid := d[p + 3 + k * 2]
				var tt := d[p + 4 + k * 2]
				for ci in comps.size():
					if comps[ci].id == cid:
						comps[ci].td = tt >> 4
						comps[ci].ta = tt & 15
						comps[ci].pred = 0
						sc.append(ci)
			_d = d
			_p = seg_end
			_bb = 0
			_bc = 0
			_scan(res, sc, qt, hts, ri)
			p = _p
			continue
		p = seg_end
	if not res.has("planes"):
		return {}
	return res


func _huff(counts: PackedByteArray, syms: PackedByteArray) -> Dictionary:
	var lut := {}
	var code := 0
	var k := 0
	for l in range(1, 17):
		for i in counts[l - 1]:
			lut[(l << 16) | code] = syms[k]
			k += 1
			code += 1
		code <<= 1
	return lut


func _bit() -> int:
	if _bc == 0:
		if _p >= _d.size():
			return 0
		var b := _d[_p]
		if b == 0xFF:
			var b2 := _d[_p + 1] if _p + 1 < _d.size() else 0xD9
			if b2 == 0:
				_p += 2
			else:
				return 0  # маркер: данные кончились, дальше нули
		else:
			_p += 1
		_bb = b
		_bc = 8
	_bc -= 1
	return (_bb >> _bc) & 1


func _recv(n: int) -> int:
	var v := 0
	for i in n:
		v = (v << 1) | _bit()
	return v


func _ext(v: int, n: int) -> int:
	if n == 0:
		return 0
	return v if v >= (1 << (n - 1)) else v - (1 << n) + 1


func _sym(lut: Dictionary) -> int:
	var code := 0
	for l in range(1, 17):
		code = (code << 1) | _bit()
		var key := (l << 16) | code
		if lut.has(key):
			return lut[key]
	return 0


func _scan(res: Dictionary, sc: Array, qt: Array, hts: Dictionary, ri: int) -> void:
	var comps: Array = res.comps
	var single := sc.size() == 1
	var mcux: int = res.mcux
	var mcuy: int = res.mcuy
	if single:
		var c0: Dictionary = comps[sc[0]]
		mcux = int(ceil(ceil(float(res.w) * int(c0.h) / int(res.hmax)) / 8.0))
		mcuy = int(ceil(ceil(float(res.h) * int(c0.v) / int(res.vmax)) / 8.0))
	var n := 0
	for my in mcuy:
		for mx in mcux:
			if ri > 0 and n > 0 and n % ri == 0:
				_bc = 0
				while _p + 1 < _d.size() and not (_d[_p] == 0xFF and _d[_p + 1] >= 0xD0 and _d[_p + 1] <= 0xD7):
					_p += 1
				_p += 2
				for ci in sc:
					comps[ci].pred = 0
			n += 1
			for ci in sc:
				var c: Dictionary = comps[ci]
				var bh := 1 if single else int(c.h)
				var bv := 1 if single else int(c.v)
				var pl: PackedByteArray = res.planes[ci]
				var pw: int = c.pw
				var ph: int = c.ph
				for by in bv:
					for bx in bh:
						var blk := _block(c, hts.get(int(c.td), {}), hts.get(16 + int(c.ta), {}), qt[int(c.tq)])
						var ox := (mx * bh + bx) * 8
						var oy := (my * bv + by) * 8
						for yy in 8:
							if oy + yy >= ph:
								break
							for xx in 8:
								if ox + xx < pw:
									pl[(oy + yy) * pw + ox + xx] = clampi(int(round(blk[yy * 8 + xx] + 128.0)), 0, 255)
				res.planes[ci] = pl


func _block(c: Dictionary, dc: Dictionary, ac: Dictionary, q: PackedInt32Array) -> PackedFloat32Array:
	var blk := PackedFloat32Array()
	blk.resize(64)
	var t := _sym(dc)
	var diff := _ext(_recv(t), t)
	c.pred = int(c.pred) + diff
	var ok_q := q.size() == 64
	blk[0] = float(int(c.pred) * (q[0] if ok_q else 1))
	var k := 1
	while k < 64:
		var rs := _sym(ac)
		var r := rs >> 4
		var s := rs & 15
		if s == 0:
			if r == 15:
				k += 16
				continue
			break
		k += r
		if k > 63:
			break
		blk[ZZ[k]] = float(_ext(_recv(s), s) * (q[k] if ok_q else 1))
		k += 1
	# обратное ДКП: строки, затем столбцы
	var tmp := PackedFloat32Array()
	tmp.resize(64)
	for y in 8:
		for x in 8:
			var s1 := 0.0
			for u in 8:
				s1 += _cos[x * 8 + u] * blk[y * 8 + u]
			tmp[y * 8 + x] = s1
	var out := PackedFloat32Array()
	out.resize(64)
	for x in 8:
		for y in 8:
			var s2 := 0.0
			for v in 8:
				s2 += _cos[y * 8 + v] * tmp[v * 8 + x]
			out[y * 8 + x] = s2
	return out


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

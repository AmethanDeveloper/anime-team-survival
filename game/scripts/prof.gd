class_name Prof
static var acc := {}
static var cnt := {}
static func add(k: String, t0: int) -> void:
	acc[k] = int(acc.get(k, 0)) + Time.get_ticks_usec() - t0
	cnt[k] = int(cnt.get(k, 0)) + 1

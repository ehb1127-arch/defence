class_name FxArt
## 효과 이미지 (art/fx/, docs/EFFECTS_TODO.md): 파일이 있으면 코드 효과 대신 이미지로 그린다.
##  - <이름>_sheet.png : 4×4 칸 16프레임 애니메이션 (왼→오, 위→아래)
##  - <이름>.png       : 한 장 그림. 커지기·회전·번쩍임·사라짐을 코드로 입혀 움직인다
##  - 배경이 투명하지 않은(검은 배경) 그림은 불러올 때 밝기를 투명도로 바꿔 검정을 없앤다

const GRID := 4
const FRAMES := 16

static var _cache := {}


## {"tex": Texture2D, "sheet": bool} 또는 없으면 {}
static func get_fx(key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]
	var out := {}
	for suffix in ["_sheet", ""]:
		var t: Texture2D = Art.tex("fx/" + key + suffix)
		if t != null:
			out = {"tex": _fix_black_bg(t), "sheet": suffix == "_sheet"}
			break
	_cache[key] = out
	return out


static func has(key: String) -> bool:
	return not get_fx(key).is_empty()


## 한 번 재생되는 효과. k = 0..1 진행도, size = 화면에서의 한 변 길이(px)
static func draw_burst(ci: CanvasItem, key: String, pos: Vector2, size: float, k: float, tint := Color.WHITE, rot := 0.0, spin := true) -> bool:
	var f := get_fx(key)
	if f.is_empty():
		return false
	k = clampf(k, 0.0, 1.0)
	var tex: Texture2D = f["tex"]
	if f["sheet"]:
		var frame := mini(FRAMES - 1, int(k * FRAMES))
		_draw_frame(ci, tex, frame, pos, Vector2(size, size), rot, tint)
		return true
	# 한 장 그림: 빠르게 커졌다가 살짝 더 커지며 사라짐
	var grow := 0.55 + 0.45 * (1.0 - pow(1.0 - minf(k / 0.35, 1.0), 3.0)) + 0.12 * k
	var alpha := minf(k / 0.12, 1.0) * (1.0 - clampf((k - 0.55) / 0.45, 0.0, 1.0))
	var flash := 1.0 + 0.6 * maxf(0.0, 1.0 - k / 0.2)   # 시작 순간 번쩍
	var r := rot + (k * 0.5 if spin else 0.0)
	var c := Color(tint.r * flash, tint.g * flash, tint.b * flash, tint.a * alpha)
	_draw_single(ci, tex, pos, Vector2(size, size) * grow, r, c)
	return true


## 계속 붙어 있는 효과 (상태이상). time = 초 단위 시계
static func draw_loop(ci: CanvasItem, key: String, pos: Vector2, size: float, time: float, tint := Color.WHITE) -> bool:
	var f := get_fx(key)
	if f.is_empty():
		return false
	var tex: Texture2D = f["tex"]
	if f["sheet"]:
		_draw_frame(ci, tex, int(time * 12.0) % FRAMES, pos, Vector2(size, size), 0.0, tint)
	else:
		var pulse := 1.0 + 0.06 * sin(time * 6.0)
		_draw_single(ci, tex, pos, Vector2(size, size) * pulse, 0.0, tint)
	return true


## 날아가는 투사체: from → to, k = 0..1
static func draw_projectile(ci: CanvasItem, key: String, from: Vector2, to: Vector2, k: float, size: float, tint := Color.WHITE) -> bool:
	var f := get_fx(key)
	if f.is_empty():
		return false
	var p := from.lerp(to, clampf(k, 0.0, 1.0))
	var ang := (to - from).angle()
	var tex: Texture2D = f["tex"]
	if f["sheet"]:
		_draw_frame(ci, tex, int(k * FRAMES) % FRAMES, p, Vector2(size, size), ang, tint)
	else:
		_draw_single(ci, tex, p, Vector2(size, size), ang, tint)
	return true


static func _draw_single(ci: CanvasItem, tex: Texture2D, pos: Vector2, size: Vector2, rot: float, col: Color) -> void:
	ci.draw_set_transform(pos, rot, Vector2.ONE)
	ci.draw_texture_rect(tex, Rect2(-size * 0.5, size), false, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _draw_frame(ci: CanvasItem, tex: Texture2D, frame: int, pos: Vector2, size: Vector2, rot: float, col: Color) -> void:
	var cell := tex.get_size() / GRID
	var src := Rect2(Vector2(frame % GRID, frame / GRID) * cell, cell)
	ci.draw_set_transform(pos, rot, Vector2.ONE)
	ci.draw_texture_rect_region(tex, Rect2(-size * 0.5, size), src, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 검은 배경 그림이면 (네 모서리가 불투명한 어두운 색) 밝기를 투명도로 바꾼다
static func _fix_black_bg(t: Texture2D) -> Texture2D:
	var img := t.get_image()
	if img == null:
		return t
	if img.is_compressed():
		if img.decompress() != OK:
			return t
	var w := img.get_width()
	var h := img.get_height()
	var dark := 0
	for p in [Vector2i(1, 1), Vector2i(w - 2, 1), Vector2i(1, h - 2), Vector2i(w - 2, h - 2)]:
		var c := img.get_pixelv(p)
		if c.a > 0.95 and c.r + c.g + c.b < 0.25:
			dark += 1
	if dark < 3:
		return t
	img.convert(Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var a := maxf(c.r, maxf(c.g, c.b))
			if a <= 0.004:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				img.set_pixel(x, y, Color(minf(c.r / a, 1.0), minf(c.g / a, 1.0), minf(c.b / a, 1.0), a))
	return ImageTexture.create_from_image(img)

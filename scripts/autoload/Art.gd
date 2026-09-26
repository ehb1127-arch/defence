extends Node
## 그림 교체 지점.
##
## art/ 폴더에 정해진 이름의 PNG 를 넣으면 코드로 그린 임시 그림 대신 그 이미지를 쓴다.
## 파일이 없으면 null 을 돌려주고, 호출하는 쪽이 Glyphs(벡터 임시 그림)로 대신 그린다.
## 목록과 권장 크기: art/README.md
##
##   Art.tex("units/sword")     -> res://art/units/sword.png
##   Art.tex("enemies/boss")    -> res://art/enemies/boss.png
##   Art.tex("icons/gold")      -> res://art/icons/gold.png
##   Art.tex("ui/button_normal")-> res://art/ui/button_normal.png (9-slice)

const ROOT := "res://art/"

## 이미지가 준비되기 전까지 칸 안에 유닛 이름을 띄울지 (기본: 끔, 선택/마우스 오버 때만 표시)
var show_unit_labels := false

var _cache := {}


func tex(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var path := ROOT + key + ".png"
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_cache[key] = t
	return t


func has(key: String) -> bool:
	return tex(key) != null


func unit(id: String) -> Texture2D:
	return tex("units/" + id)


func enemy(kind: String) -> Texture2D:
	return tex("enemies/" + kind)


func icon(name: String) -> Texture2D:
	return tex("icons/" + name)


## 9-slice 스타일박스. 이미지가 있으면 StyleBoxTexture, 없으면 null
##
## 아트 파일이 스프라이트 시트에서 잘라낸 것이라 여백/다른 패널 조각이 섞여 있어도 쓸 수 있게:
##  - 불투명한 영역 중 가장 큰 덩어리(패널 본체)만 찾아 region_rect 로 사용
##  - 본체가 이미지 가장자리에 닿아 잘려 있으면 깨진 이미지로 보고 쓰지 않음 (null → 코드 스타일)
##  - 모서리 장식이 늘어나지 않도록 모서리 크기를 본체 크기에 맞춰 자동 계산
func stylebox(key: String, content := -1.0) -> StyleBox:
	var t := tex("ui/" + key)
	if t == null:
		return null
	var r := region(t)
	if r.size == Vector2i.ZERO:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = t
	sb.region_rect = Rect2(r)
	var m := clampi(int(mini(r.size.x, r.size.y) * 0.26), 10, 96)
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m
	var cm := content if content >= 0.0 else m * 0.62
	sb.content_margin_left = cm
	sb.content_margin_right = cm
	sb.content_margin_top = cm
	sb.content_margin_bottom = cm
	return sb


var _regions := {}


func region(t: Texture2D) -> Rect2i:
	## 패널 본체 영역 (없거나 잘린 이미지면 크기 0)
	var key := t.resource_path
	if _regions.has(key):
		return _regions[key]
	var img := t.get_image()
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var step := 2
	# 불투명한 줄들의 연속 구간 중 가장 긴 것 = 본체
	var best := Vector2i(-1, -1)
	var run_start := -1
	for y in range(0, h + step, step):
		var solid := false
		if y < h:
			for x in range(0, w, step):
				if img.get_pixel(x, y).a > 0.5:
					solid = true
					break
		if solid and run_start < 0:
			run_start = y
		elif not solid and run_start >= 0:
			if y - run_start > best.y - best.x:
				best = Vector2i(run_start, y)
			run_start = -1
	var out := Rect2i()
	if best.x >= 0:
		var x0 := w
		var x1 := 0
		for y in range(best.x, mini(best.y, h), step):
			for x in range(0, w, step):
				if img.get_pixel(x, y).a > 0.5:
					x0 = mini(x0, x)
					x1 = maxi(x1, x)
		out = Rect2i(x0, best.x, x1 - x0 + 1, mini(best.y, h) - best.x)
		# 가장자리에 닿음 = 잘린 그림
		if out.position.x <= 1 or out.position.y <= 1 or out.end.x >= w - 1 or out.end.y >= h - 1:
			push_warning("art: %s 는 패널이 이미지 가장자리에서 잘려 있어 사용하지 않습니다 (%s)" % [key, out])
			out = Rect2i()
	_regions[key] = out
	return out

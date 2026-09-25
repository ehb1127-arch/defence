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
func stylebox(key: String, margin := 16) -> StyleBox:
	var t := tex("ui/" + key)
	if t == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = t
	sb.texture_margin_left = margin
	sb.texture_margin_right = margin
	sb.texture_margin_top = margin
	sb.texture_margin_bottom = margin
	sb.content_margin_left = margin * 0.6
	sb.content_margin_right = margin * 0.6
	sb.content_margin_top = margin * 0.4
	sb.content_margin_bottom = margin * 0.4
	return sb

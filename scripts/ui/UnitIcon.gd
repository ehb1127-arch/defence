class_name UnitIcon
extends Control
## UI 용 유닛 토큰 (조합표 재료, 선택 카드 초상화 등)

var unit_id := ""
var dim := false
var check := false


static func make(id: String, sz: float) -> UnitIcon:
	var u := UnitIcon.new()
	u.unit_id = id
	u.custom_minimum_size = Vector2(sz, sz)
	u.mouse_filter = Control.MOUSE_FILTER_PASS
	if id != "":
		u.tooltip_text = "%s [%s]\n%s" % [GameData.UNITS[id]["name"], GameData.RARITY_NAMES[GameData.UNITS[id]["rarity"]], GameData.UNITS[id]["desc"]]
	return u


func set_unit(id: String, p_dim := false, p_check := false) -> void:
	if id != unit_id or p_dim != dim or p_check != check:
		unit_id = id
		dim = p_dim
		check = p_check
		if id != "":
			tooltip_text = "%s [%s]\n%s" % [GameData.UNITS[id]["name"], GameData.RARITY_NAMES[GameData.UNITS[id]["rarity"]], GameData.UNITS[id]["desc"]]
		queue_redraw()


func _draw() -> void:
	if unit_id == "":
		return
	var r := minf(size.x, size.y) * 0.36
	Glyphs.draw_unit_token(self, unit_id, size * 0.5, r, 0.0, 0.35 if dim else 1.0)
	if check:
		var p := Vector2(size.x - 9, size.y - 9)
		draw_circle(p, 8, Color(0.2, 0.75, 0.35))
		Glyphs.draw(self, "check", p, 6, Color.WHITE)

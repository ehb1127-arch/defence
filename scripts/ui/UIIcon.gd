class_name UIIcon
extends Control
## 아이콘 하나 (art/icons/<name>.png 가 있으면 이미지, 없으면 벡터 임시 그림)

var icon_name := ""
var color := Color.WHITE


static func make(p_name: String, sz: float, p_color := Color.WHITE) -> UIIcon:
	var i := UIIcon.new()
	i.icon_name = p_name
	i.color = p_color
	i.custom_minimum_size = Vector2(sz, sz)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func set_icon(p_name: String, p_color := Color.WHITE) -> void:
	icon_name = p_name
	color = p_color
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y) * 0.5
	Glyphs.draw_icon(self, icon_name, size * 0.5, s * 0.92, color)

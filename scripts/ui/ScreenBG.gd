class_name ScreenBG
extends Control
## 공통 화면 배경 (이미지가 없을 때): 세로 그라데이션 + 가운데 빛 + 도는 광선 + 반짝이 + 사각 트랙
## 이미지로 바꾸려면 각 화면의 art/ui/<화면>_bg.png 를 넣으면 그쪽이 우선

var rays := true
var track := true
var center := Vector2(800, 360)
var t := 0.0
var sparks: Array = []

func _ready() -> void:
	for i in 40:
		sparks.append(Vector3(randf() * 1600, randf() * 900, randf_range(0.3, 1.0)))

func _process(delta: float) -> void:
	t += delta
	queue_redraw()

func _draw() -> void:
	var top := Color(0.2, 0.26, 0.58)
	var mid := Color(0.11, 0.13, 0.33)
	var bot := Color(0.04, 0.05, 0.13)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(1600, 0), Vector2(1600, 450), Vector2(0, 450)]), PackedColorArray([top, top, mid, mid]))
	draw_polygon(PackedVector2Array([Vector2(0, 450), Vector2(1600, 450), Vector2(1600, 900), Vector2(0, 900)]), PackedColorArray([mid, mid, bot, bot]))
	var c := center
	# 광선
	for i in (14 if rays else 0):
		var a0 := t * 0.12 + i * TAU / 14.0
		var pts := PackedVector2Array([c, c + Vector2.from_angle(a0) * 1100, c + Vector2.from_angle(a0 + 0.12) * 1100])
		draw_colored_polygon(pts, Color(0.55, 0.7, 1.0, 0.045))
	for k in 6:
		draw_circle(c, 330 - k * 50, Color(0.45, 0.6, 1.0, 0.035))
	# 바닥 원판
	for k in (3 if track else 0):
		var w := 560.0 - k * 90
		draw_set_transform(Vector2(800, 505), 0, Vector2(1, 0.22))
		draw_circle(Vector2.ZERO, w * 0.5, Color(0.02, 0.03, 0.1, 0.35 + 0.1 * k))
	draw_set_transform(Vector2.ZERO)
	# 도는 사각 트랙 (게임 정체성)
	if not track:
		_sparks()
		return
	var s := 560.0
	var r := Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s))
	draw_rect(r, Color(0.6, 0.75, 1.0, 0.06), false, 14.0)
	var per := s * 4.0
	for n in 12:
		var d := fmod(t * 60.0 + n * per / 12.0, per)
		var side := int(d / s)
		var q := d - side * s
		var p: Vector2 = [r.position + Vector2(q, 0), r.position + Vector2(s, q), r.position + Vector2(s - q, s), r.position + Vector2(0, s - q)][side]
		draw_circle(p, 6.0, Color(1, 0.4, 0.35, 0.3))
	_sparks()


func _sparks() -> void:
	for sp in sparks:
		var y := fmod(sp.y - t * 18.0 * sp.z + 900.0, 900.0)
		var x: float = sp.x + sin(t * sp.z + sp.y) * 12.0
		draw_circle(Vector2(x, y), 1.5 + sp.z * 1.6, Color(1, 0.95, 0.7, 0.25 * sp.z + 0.1 * sin(t * 3.0 + sp.x)))

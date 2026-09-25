extends Node
## 게임 전체에서 쓰는 정적 데이터: 유닛, 등급, 조합식, 적, 웨이브, 경제 수치.

enum Rarity { COMMON, RARE, EPIC, LEGEND, MYTHIC }

const RARITY_NAMES := ["일반", "희귀", "영웅", "전설", "신화"]
const RARITY_COLORS := [
	Color(0.85, 0.85, 0.85),
	Color(0.35, 0.65, 1.0),
	Color(0.75, 0.4, 1.0),
	Color(1.0, 0.65, 0.15),
	Color(1.0, 0.25, 0.3),
]

# ---------------------------------------------------------------------------
# 유닛 정의
#   dmg: 1회 공격 피해, cd: 공격 간격(초), range: 사거리(px)
#   fx: 특수 효과 (Board.gd 에서 해석)
#   skill: 신화 유닛 액티브(자동 발동) 스킬
# ---------------------------------------------------------------------------
const UNITS := {
	# ---- 일반 ----
	"sword":   {"name": "검사", "rarity": 0, "color": Color(0.8, 0.8, 0.85), "dmg": 12.0, "cd": 0.8, "range": 150.0, "fx": {}, "desc": "튼튼한 근접 전사"},
	"archer":  {"name": "궁수", "rarity": 0, "color": Color(0.55, 0.85, 0.45), "dmg": 7.0, "cd": 0.55, "range": 250.0, "fx": {}, "desc": "빠른 원거리 공격"},
	"mage":    {"name": "견습마법사", "rarity": 0, "color": Color(0.6, 0.6, 1.0), "dmg": 10.0, "cd": 1.0, "range": 210.0, "fx": {"splash": 40.0}, "desc": "작은 범위 공격"},
	"spear":   {"name": "창병", "rarity": 0, "color": Color(0.85, 0.7, 0.45), "dmg": 9.0, "cd": 0.8, "range": 175.0, "fx": {"armor_break": 5.0}, "desc": "방어력 감소"},
	"slinger": {"name": "투석병", "rarity": 0, "color": Color(0.7, 0.6, 0.55), "dmg": 8.0, "cd": 0.9, "range": 210.0, "fx": {"stun_chance": 0.06, "stun": 0.3}, "desc": "낮은 확률 기절"},
	# ---- 희귀 ----
	"knight":  {"name": "기사", "rarity": 1, "color": Color(0.5, 0.7, 1.0), "dmg": 34.0, "cd": 0.9, "range": 160.0, "fx": {"stun_chance": 0.15, "stun": 0.6}, "desc": "기절 확률 15%"},
	"sniper":  {"name": "저격수", "rarity": 1, "color": Color(0.3, 0.8, 0.6), "dmg": 45.0, "cd": 1.4, "range": 380.0, "fx": {"crit": 0.25, "crit_mult": 3.0}, "desc": "초장거리 치명타"},
	"frost":   {"name": "얼음술사", "rarity": 1, "color": Color(0.55, 0.9, 1.0), "dmg": 18.0, "cd": 1.0, "range": 230.0, "fx": {"splash": 50.0, "slow": 0.35, "slow_time": 1.5}, "desc": "범위 둔화"},
	"pyro":    {"name": "화염술사", "rarity": 1, "color": Color(1.0, 0.45, 0.2), "dmg": 22.0, "cd": 1.1, "range": 215.0, "fx": {"splash": 60.0, "burn": 0.5, "burn_time": 3.0}, "desc": "범위 화상"},
	"rogue":   {"name": "도적", "rarity": 1, "color": Color(0.6, 0.6, 0.6), "dmg": 19.0, "cd": 0.45, "range": 160.0, "fx": {"gold_chance": 0.12, "gold": 2}, "desc": "공격 시 골드 강탈"},
	# ---- 영웅 ----
	"storm":   {"name": "번개술사", "rarity": 2, "color": Color(1.0, 0.95, 0.35), "dmg": 60.0, "cd": 1.2, "range": 260.0, "fx": {"chain": 4}, "desc": "연쇄 번개 4회"},
	"berserk": {"name": "광전사", "rarity": 2, "color": Color(0.9, 0.25, 0.25), "dmg": 68.0, "cd": 0.8, "range": 160.0, "fx": {"ramp": 0.15, "ramp_max": 6}, "desc": "같은 적 공격 시 가속"},
	"alch":    {"name": "연금술사", "rarity": 2, "color": Color(0.45, 0.95, 0.3), "dmg": 40.0, "cd": 1.0, "range": 240.0, "fx": {"splash": 50.0, "poison": 0.8, "poison_time": 4.0, "armor_break": 10.0}, "desc": "독 + 방어력 감소"},
	"bard":    {"name": "음유시인", "rarity": 2, "color": Color(1.0, 0.6, 0.85), "dmg": 30.0, "cd": 1.0, "range": 230.0, "fx": {"aura_speed": 0.12}, "desc": "주변 칸 공속 +12%"},
	"ranger":  {"name": "사냥꾼", "rarity": 2, "color": Color(0.35, 0.7, 0.3), "dmg": 44.0, "cd": 0.9, "range": 290.0, "fx": {"multishot": 3}, "desc": "3연발 동시 사격"},
	# ---- 전설 ----
	"dragoon": {"name": "용기사", "rarity": 3, "color": Color(1.0, 0.55, 0.1), "dmg": 260.0, "cd": 1.3, "range": 210.0, "fx": {"splash": 90.0}, "desc": "거대한 범위 공격"},
	"archmage": {"name": "대마법사", "rarity": 3, "color": Color(0.55, 0.45, 1.0), "dmg": 180.0, "cd": 1.2, "range": 290.0, "fx": {"meteor_every": 5, "meteor_mult": 6.0, "meteor_radius": 120.0}, "desc": "5회마다 메테오"},
	"assassin": {"name": "암살자", "rarity": 3, "color": Color(0.35, 0.3, 0.45), "dmg": 220.0, "cd": 0.7, "range": 175.0, "fx": {"execute": 0.12, "crit": 0.3, "crit_mult": 2.5}, "desc": "체력 12% 이하 처형"},
	"guardian": {"name": "수호천사", "rarity": 3, "color": Color(1.0, 0.95, 0.7), "dmg": 120.0, "cd": 1.0, "range": 250.0, "fx": {"slow_aura": 0.3, "stun_chance": 0.2, "stun": 0.8}, "desc": "사거리 내 적 둔화"},
	# ---- 신화 ----
	"phoenix": {"name": "불사조", "rarity": 4, "color": Color(1.0, 0.35, 0.1), "dmg": 700.0, "cd": 1.0, "range": 310.0, "fx": {"splash": 110.0, "burn": 0.8, "burn_time": 4.0},
		"skill": {"id": "firestorm", "name": "화염 폭풍", "cd": 12.0}, "desc": "스킬: 사거리 내 전체 5배 피해"},
	"thunder": {"name": "뇌신", "rarity": 4, "color": Color(0.9, 0.9, 0.2), "dmg": 450.0, "cd": 0.6, "range": 330.0, "fx": {"chain": 8},
		"skill": {"id": "judgement", "name": "천둥 심판", "cd": 10.0}, "desc": "스킬: 필드 전체 번개 + 기절"},
	"chrono":  {"name": "시간술사", "rarity": 4, "color": Color(0.4, 0.95, 0.95), "dmg": 300.0, "cd": 0.9, "range": 310.0, "fx": {"splash": 70.0, "slow": 0.5, "slow_time": 2.0},
		"skill": {"id": "timestop", "name": "시간 정지", "cd": 15.0}, "desc": "스킬: 모든 적 2.5초 정지"},
	"midas":   {"name": "황금왕", "rarity": 4, "color": Color(1.0, 0.85, 0.2), "dmg": 380.0, "cd": 0.7, "range": 270.0, "fx": {"gold_chance": 0.5, "gold": 5},
		"skill": {"id": "goldrain", "name": "황금비", "cd": 20.0}, "desc": "스킬: 보유 골드 10% 이자"},
	"reaper":  {"name": "그림자군주", "rarity": 4, "color": Color(0.55, 0.2, 0.7), "dmg": 900.0, "cd": 1.1, "range": 230.0, "fx": {"execute": 0.25, "crit": 0.4, "crit_mult": 3.0},
		"skill": {"id": "reap", "name": "영혼 수확", "cd": 14.0}, "desc": "스킬: 체력 높은 적 3명 즉사"},
}

## 스냅샷/네트워크 직렬화를 위한 고정 순서
const UNIT_ORDER := [
	"sword", "archer", "mage", "spear", "slinger",
	"knight", "sniper", "frost", "pyro", "rogue",
	"storm", "berserk", "alch", "bard", "ranger",
	"dragoon", "archmage", "assassin", "guardian",
	"phoenix", "thunder", "chrono", "midas", "reaper",
]

## 신화 조합식: 결과 -> 재료 목록 (중복 허용)
const RECIPES := {
	"phoenix": ["pyro", "pyro", "berserk", "dragoon"],
	"thunder": ["storm", "storm", "sniper", "archmage"],
	"chrono":  ["frost", "frost", "bard", "guardian"],
	"midas":   ["rogue", "rogue", "rogue", "alch", "assassin"],
	"reaper":  ["knight", "knight", "ranger", "assassin"],
}

# ---------------------------------------------------------------------------
# 적 정의 (hp 는 해당 웨이브 기본 체력의 배수)
#   weight: 필드 적 수 계산 시 가중치
# ---------------------------------------------------------------------------
const ENEMIES := {
	"normal":   {"hp": 1.0, "speed": 70.0, "armor": 0.0, "weight": 1, "size": 9.0, "color": Color(0.85, 0.3, 0.3)},
	"fast":     {"hp": 0.6, "speed": 125.0, "armor": 0.0, "weight": 1, "size": 7.0, "color": Color(1.0, 0.75, 0.2)},
	"tank":     {"hp": 2.6, "speed": 48.0, "armor": 30.0, "weight": 1, "size": 12.0, "color": Color(0.5, 0.5, 0.6)},
	"shield":   {"hp": 1.0, "speed": 68.0, "armor": 0.0, "weight": 1, "size": 9.0, "color": Color(0.35, 0.55, 0.95), "shield": 1.0},
	"splitter": {"hp": 1.2, "speed": 65.0, "armor": 0.0, "weight": 1, "size": 10.0, "color": Color(0.4, 0.85, 0.4), "split": 2},
	"mini":     {"hp": 0.35, "speed": 110.0, "armor": 0.0, "weight": 1, "size": 6.0, "color": Color(0.5, 0.95, 0.5)},
	"healer":   {"hp": 1.2, "speed": 66.0, "armor": 5.0, "weight": 1, "size": 9.0, "color": Color(1.0, 0.55, 0.8), "heal": 0.05},
	"boss":     {"hp": 55.0, "speed": 42.0, "armor": 20.0, "weight": 20, "size": 20.0, "color": Color(0.7, 0.1, 0.5)},
	"elite":    {"hp": 14.0, "speed": 55.0, "armor": 15.0, "weight": 5, "size": 15.0, "color": Color(0.9, 0.1, 0.1)},
	"goblin":   {"hp": 6.0, "speed": 150.0, "armor": 0.0, "weight": 0, "size": 9.0, "color": Color(1.0, 0.85, 0.1)},
}
const ENEMY_ORDER := ["normal", "fast", "tank", "shield", "splitter", "mini", "healer", "boss", "elite", "goblin"]

const BOSS_NAMES := ["오우거 대장", "해골 군주", "화염 골렘", "심연의 눈"]

# ---------------------------------------------------------------------------
# 게임 규칙 수치
# ---------------------------------------------------------------------------
const FINAL_WAVE := 40
const WAVE_TIME := 20.0
const BOSS_WAVE_TIME := 45.0
const SPAWN_PER_WAVE := 20
const SPAWN_INTERVAL := 0.6
const ENEMY_LIMIT := 100
const COOP_ENEMY_LIMIT := 180
const BASE_HP := 22.0
const HP_GROWTH := 1.19
const START_GOLD := 100
const START_GEMS := 2
const SUMMON_BASE_COST := 20
const SUMMON_COST_STEP := 1
const SELL_GOLD := [8, 20, 50, 0, 0]
const SELL_GEMS := [0, 0, 0, 2, 0]
const MAX_STACK := 3
const COOP_BLAST_NEED := 250
const MAX_UPGRADE := 20
const MAX_LUCK := 5

## 소환 확률(일반, 희귀, 영웅, 전설) - 행운 레벨에 따라 이동
const SUMMON_PROBS := [0.68, 0.265, 0.05, 0.005]
const LUCK_SHIFT := [-0.045, 0.025, 0.016, 0.004]

## 도박: [보석 비용, 성공 확률, 결과 등급]
const GAMBLES := [
	{"name": "영웅 도박", "gems": 1, "chance": 0.6, "rarity": 2},
	{"name": "전설 도박", "gems": 2, "chance": 0.25, "rarity": 3},
]

## 대전 모드 공격: 적 보내기
const ATTACKS := [
	{"id": "swarm", "name": "잡몹 떼", "gold": 40, "gems": 0, "desc": "빠른 적 6마리"},
	{"id": "elite", "name": "정예 괴수", "gold": 150, "gems": 0, "desc": "정예 1마리(가중치 5)"},
	{"id": "curse", "name": "저주", "gold": 0, "gems": 2, "desc": "상대 공속 -30% 10초"},
]

## 강화 트랙
const UPGRADES := [
	{"id": "low", "name": "일반/희귀", "rarities": [0, 1], "cur": "gold", "base": 30, "step": 20},
	{"id": "mid", "name": "영웅", "rarities": [2], "cur": "gold", "base": 60, "step": 35},
	{"id": "high", "name": "전설/신화", "rarities": [3, 4], "cur": "gems", "base": 1, "step": 1},
	{"id": "luck", "name": "소환 행운", "rarities": [], "cur": "gold", "base": 100, "step": 100},
]
const UPGRADE_DMG_PER_LEVEL := 0.12

## 랜덤 이벤트 (5웨이브마다)
const EVENTS := [
	{"id": "goblin", "name": "황금 고블린 출현!", "desc": "잡으면 골드 대박 + 보석"},
	{"id": "lucky", "name": "행운의 시간!", "desc": "15초간 소환 비용 절반"},
	{"id": "frenzy", "name": "광란!", "desc": "이번 웨이브 적 이동속도 +30%"},
	{"id": "supply", "name": "보급품 도착!", "desc": "무료 소환 3회"},
	{"id": "storm", "name": "번개 폭풍!", "desc": "필드 모든 적에게 체력 25% 피해"},
	{"id": "gemrain", "name": "보석비!", "desc": "보석 +2"},
]

## 도전 과제
const MISSIONS := [
	{"id": "first_epic", "name": "첫 영웅", "desc": "영웅 유닛 획득", "gold": 60, "gems": 0},
	{"id": "first_legend", "name": "전설의 시작", "desc": "전설 유닛 획득", "gold": 0, "gems": 2},
	{"id": "first_mythic", "name": "신화 강림", "desc": "신화 유닛 조합", "gold": 300, "gems": 3},
	{"id": "kill_500", "name": "학살자", "desc": "적 500마리 처치", "gold": 200, "gems": 1},
	{"id": "full_board", "name": "만원 사례", "desc": "18칸 이상 채우기", "gold": 100, "gems": 0},
	{"id": "gamble_win3", "name": "타짜", "desc": "도박 3회 성공", "gold": 0, "gems": 2},
	{"id": "gamble_lose3", "name": "눈물의 도박", "desc": "도박 3회 연속 실패", "gold": 0, "gems": 3},
	{"id": "chest_5", "name": "보물 사냥꾼", "desc": "보물상자 5개 열기", "gold": 150, "gems": 1},
]


func unit(id: String) -> Dictionary:
	return UNITS.get(id, {})


func units_of_rarity(r: int) -> Array:
	var out: Array = []
	for id in UNIT_ORDER:
		if UNITS[id]["rarity"] == r:
			out.append(id)
	return out


func unit_index(id: String) -> int:
	return UNIT_ORDER.find(id)


func enemy_index(kind: String) -> int:
	return ENEMY_ORDER.find(kind)


func summon_probs(luck: int) -> Array:
	var p: Array = []
	for i in SUMMON_PROBS.size():
		p.append(maxf(0.0, SUMMON_PROBS[i] + LUCK_SHIFT[i] * luck))
	return p


func roll_summon_rarity(rng: RandomNumberGenerator, luck: int) -> int:
	var p := summon_probs(luck)
	var total := 0.0
	for v in p:
		total += v
	var r := rng.randf() * total
	for i in p.size():
		r -= p[i]
		if r <= 0.0:
			return i
	return 0


func random_unit_of(rng: RandomNumberGenerator, rarity: int) -> String:
	var pool := units_of_rarity(rarity)
	return pool[rng.randi() % pool.size()]


func wave_hp(wave: int) -> float:
	var hp := BASE_HP * pow(HP_GROWTH, wave - 1)
	# 최종 웨이브 이후(대전 연장전)는 더 가파르게 증가
	if wave > FINAL_WAVE:
		hp *= pow(1.12, wave - FINAL_WAVE)
	return hp


func is_boss_wave(wave: int) -> bool:
	return wave % 10 == 0


## 웨이브별 등장 적 구성 (가중치 목록)
func wave_mix(wave: int) -> Array:
	var mix: Array = [["normal", 10]]
	if wave >= 3:
		mix.append(["fast", 4])
	if wave >= 6:
		mix.append(["tank", 3])
	if wave >= 12:
		mix.append(["shield", 3])
	if wave >= 16:
		mix.append(["splitter", 2])
	if wave >= 22:
		mix.append(["healer", 2])
	return mix


func pick_enemy(rng: RandomNumberGenerator, wave: int) -> String:
	var mix := wave_mix(wave)
	var total := 0
	for m in mix:
		total += m[1]
	var r := rng.randi() % total
	for m in mix:
		r -= m[1]
		if r < 0:
			return m[0]
	return "normal"


func upgrade_cost(track: int, level: int) -> int:
	var u: Dictionary = UPGRADES[track]
	return u["base"] + u["step"] * level


func recipe_text(mythic: String) -> String:
	var counts := {}
	for m in RECIPES[mythic]:
		counts[m] = counts.get(m, 0) + 1
	var parts: Array = []
	for k in counts:
		var s: String = UNITS[k]["name"]
		if counts[k] > 1:
			s += " x%d" % counts[k]
		parts.append(s)
	return " + ".join(parts)


var _theme: Theme


## 모든 UI 가 공유하는 테마 (버튼 스타일 등)
func ui_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	var f := load("res://fonts/NanumSquareRoundB.ttf")
	if f:
		t.default_font = f
	t.default_font_size = 16
	var states := {
		"normal": Color(0.2, 0.23, 0.32),
		"hover": Color(0.27, 0.31, 0.44),
		"pressed": Color(0.14, 0.16, 0.22),
		"disabled": Color(0.13, 0.14, 0.18),
		"focus": Color(0, 0, 0, 0),
	}
	for s in states:
		var sb := StyleBoxFlat.new()
		sb.bg_color = states[s]
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(6)
		if s == "focus":
			sb.draw_center = false
		else:
			sb.border_color = Color(1, 1, 1, 0.12 if s != "hover" else 0.3)
			sb.set_border_width_all(1)
			sb.border_width_bottom = 3 if s != "pressed" else 1
		t.set_stylebox(s, "Button", sb)
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.47, 0.52))
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	var tab_sel := StyleBoxFlat.new()
	tab_sel.bg_color = Color(0.25, 0.29, 0.4)
	tab_sel.set_corner_radius_all(6)
	tab_sel.set_content_margin_all(6)
	tab_sel.content_margin_left = 12
	tab_sel.content_margin_right = 12
	var tab_un := tab_sel.duplicate()
	tab_un.bg_color = Color(0.14, 0.16, 0.21)
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab_un)
	t.set_stylebox("tab_hovered", "TabContainer", tab_sel)
	var tab_panel := StyleBoxFlat.new()
	tab_panel.bg_color = Color(0.12, 0.13, 0.18)
	tab_panel.set_corner_radius_all(6)
	tab_panel.set_content_margin_all(8)
	t.set_stylebox("panel", "TabContainer", tab_panel)
	_theme = t
	return t

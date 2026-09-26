class_name EnemyState
extends RefCounted
## 트랙 위를 도는 적 하나의 상태. 그리기/시뮬레이션은 Board 가 담당한다.

var id := 0
var kind := "normal"
var dist := 0.0          # 누적 이동 거리 (타겟 우선순위 = 가장 멀리 간 적)
var pos := Vector2.ZERO
var hp := 1.0
var max_hp := 1.0
var shield := 0.0
var max_shield := 0.0
var armor := 0.0
var armor_break := 0.0
var speed := 60.0
var weight := 1
var size := 8.0
var color := Color.WHITE
var slow := 0.0
var slow_t := 0.0
var aura_slow := 0.0
var stun_t := 0.0
var burn_dps := 0.0
var burn_t := 0.0
var poison_dps := 0.0
var poison_t := 0.0
var heal := 0.0
var heal_t := 1.0
var split := 0
var flash := 0.0
var alive := true
var is_boss := false
var boss_name := ""
var enraged := false
var wobble := 0.0
# 보스 스킬
var skills: Array = []          # [[id, 쿨타임], ...]
var skill_cd: Array = []
var casting := ""
var cast_t := 0.0
var buff_t := 0.0               # 돌진 (이동속도 증가)
var shield_t := 0.0             # 용암 방패 (피해 감소)
var phase2 := false
var debuff_tier := 0             # 방해 기술 세기 단계 (Board._debuff_tier)
var freeze_t := 0.0             # 빙결 (표시용)
# 적 영웅
var hero := ""                  # 적 영웅 종류 id (thief/shaman/berserker/warlord)
var art := ""                   # 전용 그림 키: art/enemies/<art>.png (없으면 종류 그림)
var lap := 0                    # 도적: 몇 바퀴 돌았나
var skill_t := 0.0              # 주술사/장군: 능력 주기
var dash_t := 5.0               # 적 영웅 돌진 주기
var sent := false               # 대전: 상대가 보낸 적 (지배 불가, 처치 보석 없음)
var no_mc := false              # 지배 불가 (보낸 적, 보스 분신 등)


func setup(k: String, base_hp: float) -> void:
	kind = k
	var d: Dictionary = GameData.ENEMIES[k]
	max_hp = base_hp * d["hp"]
	hp = max_hp
	speed = d["speed"]
	armor = d["armor"]
	weight = d["weight"]
	size = d["size"]
	color = d["color"]
	if d.has("shield"):
		max_shield = max_hp * d["shield"]
		shield = max_shield
	heal = d.get("heal", 0.0)
	split = d.get("split", 0)
	is_boss = k == "boss"


func hp_ratio() -> float:
	return clampf(hp / max_hp, 0.0, 1.0)


func effective_armor() -> float:
	return clampf(armor - armor_break, 0.0, 80.0)


func status_flags() -> int:
	var f := 0
	if slow_t > 0.0 or aura_slow > 0.0:
		f |= 1
	if stun_t > 0.0:
		f |= 2
	if burn_t > 0.0 or poison_t > 0.0:
		f |= 4
	if shield > 0.0:
		f |= 8
	if enraged:
		f |= 16
	if casting != "":
		f |= 32
	if shield_t > 0.0:
		f |= 64
	return f

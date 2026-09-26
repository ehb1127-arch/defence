extends Node

## 게임 이름 변경(사각 디펜스 → 결계 수호대)으로 저장 폴더가 바뀌어서, 예전 폴더의 저장 파일을 한 번 옮긴다.
## (안드로이드는 앱 내부 폴더라 이름과 무관)
const _OLD_USER_DIR := "godot/app_userdata/사각 디펜스 (Square Defense)"
const _USER_FILES := ["profile.cfg", "online.cfg", "server_db.json", "server_iap.json"]


func _init() -> void:
	var old := OS.get_data_dir().path_join(_OLD_USER_DIR)
	if not DirAccess.dir_exists_absolute(old):
		return
	for f in _USER_FILES:
		var src := old.path_join(f)
		if FileAccess.file_exists(src) and not FileAccess.file_exists("user://" + f):
			DirAccess.copy_absolute(src, ProjectSettings.globalize_path("user://" + f))

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
	"sword":   {"glyph": "blade", "name": "검사", "rarity": 0, "color": Color(0.8, 0.8, 0.85), "dmg": 12.0, "cd": 0.8, "range": 150.0, "fx": {}, "desc": "튼튼한 근접 전사"},
	"archer":  {"glyph": "bow", "name": "궁수", "rarity": 0, "color": Color(0.55, 0.85, 0.45), "dmg": 7.0, "cd": 0.55, "range": 250.0, "fx": {}, "desc": "빠른 원거리 공격"},
	"mage":    {"glyph": "orb", "name": "견습마법사", "rarity": 0, "color": Color(0.6, 0.6, 1.0), "dmg": 10.0, "cd": 1.0, "range": 210.0, "fx": {"splash": 40.0}, "desc": "작은 범위 공격"},
	"spear":   {"glyph": "spear", "name": "창병", "rarity": 0, "color": Color(0.85, 0.7, 0.45), "dmg": 9.0, "cd": 0.8, "range": 175.0, "fx": {"armor_break": 5.0, "knockback": 8.0}, "desc": "방어력 감소 + 약한 넉백"},
	"slinger": {"glyph": "rock", "name": "투석병", "rarity": 0, "color": Color(0.7, 0.6, 0.55), "dmg": 8.0, "cd": 0.9, "range": 210.0, "fx": {"stun_chance": 0.06, "stun": 0.3}, "desc": "낮은 확률 기절"},
	# ---- 희귀 ----
	"knight":  {"glyph": "shield", "name": "기사", "rarity": 1, "color": Color(0.5, 0.7, 1.0), "dmg": 34.0, "cd": 0.9, "range": 160.0, "fx": {"stun_chance": 0.15, "stun": 0.6, "knockback": 22.0}, "desc": "기절 15% + 넉백"},
	"sniper":  {"glyph": "scope", "name": "저격수", "rarity": 1, "color": Color(0.3, 0.8, 0.6), "dmg": 45.0, "cd": 1.4, "range": 380.0, "fx": {"crit": 0.25, "crit_mult": 3.0, "pierce": 1}, "desc": "초장거리 관통 치명타"},
	"frost":   {"glyph": "snow", "name": "얼음술사", "rarity": 1, "color": Color(0.55, 0.9, 1.0), "dmg": 18.0, "cd": 1.0, "range": 230.0, "fx": {"splash": 50.0, "slow": 0.4, "slow_time": 1.8, "freeze_chance": 0.15}, "desc": "범위 둔화 40% + 15% 확률 빙결"},
	"pyro":    {"glyph": "flame", "name": "화염술사", "rarity": 1, "color": Color(1.0, 0.45, 0.2), "dmg": 22.0, "cd": 1.1, "range": 215.0, "fx": {"splash": 60.0, "burn": 0.5, "burn_time": 3.0}, "desc": "범위 화상"},
	"rogue":   {"glyph": "coin", "name": "도적", "rarity": 1, "color": Color(0.6, 0.6, 0.6), "dmg": 19.0, "cd": 0.45, "range": 160.0, "fx": {"gold_chance": 0.12, "gold": 2}, "desc": "공격 시 골드 강탈"},
	# ---- 영웅 ----
	"storm":   {"glyph": "bolt", "name": "번개술사", "rarity": 2, "color": Color(1.0, 0.95, 0.35), "dmg": 60.0, "cd": 1.2, "range": 260.0, "fx": {"chain": 4}, "desc": "연쇄 번개 4회"},
	"berserk": {"glyph": "axe", "name": "광전사", "rarity": 2, "color": Color(0.9, 0.25, 0.25), "dmg": 68.0, "cd": 0.8, "range": 160.0, "fx": {"ramp": 0.15, "ramp_max": 6}, "desc": "같은 적 공격 시 가속"},
	"alch":    {"glyph": "flask", "name": "연금술사", "rarity": 2, "color": Color(0.45, 0.95, 0.3), "dmg": 40.0, "cd": 1.0, "range": 240.0, "fx": {"splash": 50.0, "poison": 0.8, "poison_time": 4.0, "armor_break": 10.0}, "desc": "독 + 방어력 감소"},
	"bard":    {"glyph": "note", "name": "음유시인", "rarity": 2, "color": Color(1.0, 0.6, 0.85), "dmg": 30.0, "cd": 1.0, "range": 230.0, "fx": {"aura_speed": 0.12}, "desc": "주변 칸 공속 +12%"},
	"ranger":  {"glyph": "arrows", "name": "사냥꾼", "rarity": 2, "color": Color(0.35, 0.7, 0.3), "dmg": 44.0, "cd": 0.9, "range": 290.0, "fx": {"multishot": 3}, "desc": "3연발 동시 사격"},
	# ---- 전설 ----
	"dragoon": {"glyph": "wing", "name": "용기사", "rarity": 3, "color": Color(1.0, 0.55, 0.1), "dmg": 260.0, "cd": 1.3, "range": 210.0, "fx": {"splash": 90.0}, "desc": "거대한 범위 공격"},
	"archmage": {"glyph": "meteor", "name": "대마법사", "rarity": 3, "color": Color(0.55, 0.45, 1.0), "dmg": 180.0, "cd": 1.2, "range": 290.0, "fx": {"meteor_every": 5, "meteor_mult": 6.0, "meteor_radius": 120.0}, "desc": "5회마다 메테오"},
	"assassin": {"glyph": "dagger", "name": "암살자", "rarity": 3, "color": Color(0.35, 0.3, 0.45), "dmg": 220.0, "cd": 0.7, "range": 175.0, "fx": {"execute": 0.12, "crit": 0.3, "crit_mult": 2.5}, "desc": "체력 12% 이하 처형"},
	"guardian": {"glyph": "halo", "name": "수호천사", "rarity": 3, "color": Color(1.0, 0.95, 0.7), "dmg": 120.0, "cd": 1.0, "range": 250.0, "fx": {"slow_aura": 0.3, "stun_chance": 0.2, "stun": 0.8, "knockback": 30.0}, "desc": "둔화 오라 + 넉백"},
	# ---- 신화 ----
	"phoenix": {"glyph": "phoenix", "name": "불사조", "rarity": 4, "color": Color(1.0, 0.35, 0.1), "dmg": 640.0, "cd": 1.0, "range": 310.0, "fx": {"splash": 110.0, "burn": 0.8, "burn_time": 4.0},
		"skill": {"id": "firestorm", "name": "화염 폭풍", "cd": 12.0}, "desc": "스킬: 사거리 내 전체 4배 피해"},
	"thunder": {"glyph": "bolt2", "name": "뇌신", "rarity": 4, "color": Color(0.9, 0.9, 0.2), "dmg": 450.0, "cd": 0.6, "range": 330.0, "fx": {"chain": 8},
		"skill": {"id": "judgement", "name": "천둥 심판", "cd": 10.0}, "desc": "스킬: 필드 전체 번개 + 기절"},
	"chrono":  {"glyph": "clock", "name": "시간술사", "rarity": 4, "color": Color(0.4, 0.95, 0.95), "dmg": 300.0, "cd": 0.9, "range": 310.0, "fx": {"splash": 70.0, "slow": 0.5, "slow_time": 2.0},
		"skill": {"id": "timestop", "name": "시간 정지", "cd": 15.0}, "desc": "스킬: 모든 적 2.5초 정지"},
	"midas":   {"glyph": "crown", "name": "황금왕", "rarity": 4, "color": Color(1.0, 0.85, 0.2), "dmg": 420.0, "cd": 0.7, "range": 270.0, "fx": {"gold_chance": 0.5, "gold": 5},
		"skill": {"id": "goldrain", "name": "황금비", "cd": 16.0}, "desc": "스킬: 골드·보석 + 금화 폭격"},
	"reaper":  {"glyph": "skull", "name": "그림자군주", "rarity": 4, "color": Color(0.55, 0.2, 0.7), "dmg": 600.0, "cd": 1.1, "range": 230.0, "fx": {"execute": 0.15, "crit": 0.3, "crit_mult": 2.5},
		"skill": {"id": "reap", "name": "영혼 수확", "cd": 15.0}, "desc": "스킬: 체력 높은 적 2명 즉사"},
	# ---- 신화 (2차): 그림(art/units/<id>.png)이 없으면 문양 토큰으로 그린다. atk = 공격 연출 (없으면 문양 기준) ----
	"titan":   {"glyph": "rock", "atk": "bash", "name": "대지거신", "rarity": 4, "color": Color(0.8, 0.6, 0.4), "dmg": 820.0, "cd": 1.2, "range": 190.0, "fx": {"splash": 70.0, "stun_chance": 0.2, "stun": 0.6, "knockback": 18.0},
		"skill": {"id": "quake", "name": "대지 강타", "cd": 13.0}, "desc": "스킬: 주변 적 기절 + 큰 피해"},
	"paladin": {"glyph": "shield", "atk": "holy", "name": "성기사", "rarity": 4, "color": Color(1.0, 0.9, 0.55), "dmg": 520.0, "cd": 0.9, "range": 220.0, "fx": {"armor_break": 15.0, "stun_chance": 0.12, "stun": 0.5, "slow_aura": 0.2},
		"skill": {"id": "bless", "name": "신성 축복", "cd": 16.0}, "desc": "스킬: 아군 공속 증가 + 적 방어 감소"},
	"plague":  {"glyph": "flask", "atk": "flask", "name": "역병군주", "rarity": 4, "color": Color(0.55, 0.9, 0.25), "dmg": 380.0, "cd": 1.0, "range": 280.0, "fx": {"splash": 80.0, "poison": 1.0, "poison_time": 5.0, "armor_break": 12.0},
		"skill": {"id": "plague", "name": "역병 확산", "cd": 12.0}, "desc": "스킬: 모든 적 맹독 + 방어 감소"},
	"windgod": {"glyph": "arrows", "atk": "arrow", "name": "천궁", "rarity": 4, "color": Color(0.55, 1.0, 0.8), "dmg": 300.0, "cd": 0.5, "range": 360.0, "fx": {"multishot": 4, "crit": 0.2, "crit_mult": 2.5},
		"skill": {"id": "arrowrain", "name": "화살비", "cd": 11.0}, "desc": "스킬: 하늘에서 화살 비"},
	"frostwyrm": {"glyph": "snow", "atk": "ice", "name": "빙룡", "rarity": 4, "color": Color(0.45, 0.75, 1.0), "dmg": 560.0, "cd": 1.1, "range": 260.0, "fx": {"splash": 90.0, "slow": 0.45, "slow_time": 2.0, "freeze_chance": 0.1},
		"skill": {"id": "breath", "name": "빙결 숨결", "cd": 14.0}, "desc": "스킬: 적이 많은 변 전체 빙결"},
	"voidmage": {"glyph": "orb", "atk": "zap", "name": "공허술사", "rarity": 4, "color": Color(0.65, 0.4, 1.0), "dmg": 480.0, "cd": 1.0, "range": 300.0, "fx": {"chain": 3, "splash": 50.0, "slow": 0.3, "slow_time": 1.5},
		"skill": {"id": "blackhole", "name": "블랙홀", "cd": 15.0}, "desc": "스킬: 적을 한곳에 모아 폭발"},
}

## 스냅샷/네트워크 직렬화를 위한 고정 순서
const UNIT_ORDER := [
	"sword", "archer", "mage", "spear", "slinger",
	"knight", "sniper", "frost", "pyro", "rogue",
	"storm", "berserk", "alch", "bard", "ranger",
	"dragoon", "archmage", "assassin", "guardian",
	"phoenix", "thunder", "chrono", "midas", "reaper",
	# 뒤에만 추가 (스냅샷이 순서 번호를 쓴다)
	"titan", "paladin", "plague", "windgod", "frostwyrm", "voidmage",
]

## 신화 조합식: 결과 -> 재료 목록 (중복 허용)
const RECIPES := {
	"phoenix": ["pyro", "pyro", "berserk", "dragoon"],
	"thunder": ["storm", "storm", "sniper", "archmage"],
	"chrono":  ["frost", "frost", "bard", "guardian"],
	"midas":   ["rogue", "rogue", "rogue", "alch", "assassin"],
	"reaper":  ["knight", "knight", "rogue", "ranger", "assassin"],
	"titan":   ["sword", "sword", "sword", "berserk", "dragoon"],
	"paladin": ["spear", "spear", "knight", "bard", "guardian"],
	"plague":  ["mage", "mage", "alch", "alch", "archmage"],
	"windgod": ["archer", "archer", "sniper", "ranger", "guardian"],
	"frostwyrm": ["slinger", "slinger", "frost", "storm", "dragoon"],
	"voidmage": ["mage", "pyro", "frost", "storm", "archmage"],
}
## 전설은 네 종뿐이라 신화끼리 전설을 두고 경쟁한다 (한 판에 신화 몇 개만 완성 가능)

# ---------------------------------------------------------------------------
# 적 정의 (hp 는 해당 라운드 기본 체력의 배수)
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
	"boss":     {"hp": 1.0, "speed": 42.0, "armor": 20.0, "weight": 20, "size": 20.0, "color": Color(0.7, 0.1, 0.5)},
	"elite":    {"hp": 14.0, "speed": 55.0, "armor": 15.0, "weight": 5, "size": 15.0, "color": Color(0.9, 0.1, 0.1)},
	"goblin":   {"hp": 6.0, "speed": 150.0, "armor": 0.0, "weight": 0, "size": 9.0, "color": Color(1.0, 0.85, 0.1)},
	"bonus":    {"hp": 5.0, "speed": 52.0, "armor": 0.0, "weight": 0, "size": 13.0, "color": Color(1.0, 0.68, 0.75)},
	"midboss":  {"hp": 30.0, "speed": 46.0, "armor": 20.0, "weight": 10, "size": 18.0, "color": Color(0.75, 0.3, 0.95)},
	"hero":     {"hp": 1.0, "speed": 60.0, "armor": 10.0, "weight": 3, "size": 14.0, "color": Color(1.0, 0.4, 0.2)},
}
const ENEMY_ORDER := ["normal", "fast", "tank", "shield", "splitter", "mini", "healer", "boss", "elite", "goblin", "bonus", "midboss", "hero"]

## 중간보스: 7·17·27·37 라운드 (제한시간 없음, 대신 무게 10 - 오래 두면 한도가 빨리 참)
const MIDBOSS_NAMES := ["늑대 두목", "독거미 여왕", "얼음 거인", "그림자 기사"]
const MIDBOSS_ART := ["midboss_wolf", "midboss_spider", "midboss_giant", "midboss_knight"]
## 무한 모드 10·20·30·40 라운드 보스 그림 (스토리는 Story.BOSS_CHARS)
const BOSS_ART := ["boss_ogre", "boss_lich", "boss_golem", "boss_eye"]

## 적 영웅: 4라운드부터 일반 라운드에 가끔 등장. 각자 특수 능력으로 긴장감을 준다
const ENEMY_HEROES := [
	{"id": "thief", "name": "그림자 도적", "hp": 7.0, "speed": 130.0, "armor": 0.0, "color": Color(0.55, 0.45, 0.95), "desc": "한 바퀴 돌 때마다 골드를 훔쳐요"},
	{"id": "shaman", "name": "역병 주술사", "hp": 9.0, "speed": 76.0, "armor": 5.0, "color": Color(0.45, 0.9, 0.35), "desc": "주변 적의 체력을 회복시켜요"},
	{"id": "berserker", "name": "피의 광전사", "hp": 11.0, "speed": 80.0, "armor": 10.0, "color": Color(1.0, 0.3, 0.25), "desc": "체력이 줄수록 빨라져요"},
	{"id": "warlord", "name": "철갑 장군", "hp": 13.0, "speed": 64.0, "armor": 35.0, "color": Color(0.75, 0.75, 0.85), "desc": "주변 적에게 방어막을 씌워요"},
]
const HERO_CHANCE := 0.3        # 일반 라운드마다 적 영웅 등장 확률
const HERO_FROM_WAVE := 4

## 지배(마인드 컨트롤): 보석으로 트랙 위의 강한 적 하나를 내 유닛으로 빼앗기
const MC_GEMS := 4
const MC_LEGEND_GEMS := 9     # 중간보스(전설이 되는 적) 지배는 더 비싸게
const MC_COOLDOWN := 35.0
## 빼앗은 적 → 얻는 유닛 등급
## 보스·중간보스는 지배할 수 없다 (적 영웅·정예까지)
const MC_RARITY := {"normal": 1, "fast": 1, "mini": 1, "tank": 1, "shield": 1, "splitter": 1, "healer": 2, "elite": 2, "hero": 2}
const MC_PRIORITY := ["hero", "elite", "tank", "healer", "shield", "splitter", "normal", "fast", "mini"]


func is_midboss_wave(wave: int) -> bool:
	return wave % 10 == 7


func enemy_hero(id: String) -> Dictionary:
	for h in ENEMY_HEROES:
		if h["id"] == id:
			return h
	return {}

const BOSS_NAMES := ["오우거 대장", "해골 군주", "화염 골렘", "심연의 눈"]

# ---------------------------------------------------------------------------
# 게임 규칙 수치
# ---------------------------------------------------------------------------
const FINAL_WAVE := 40
const WAVE_TIME := 20.0
const BOSS_WAVE_TIME := 60.0
const BONUS_WAVE_TIME := 25.0
const BONUS_COUNT := 10
const PREP_TIME := 8.0
const BOSS_HP_MULT := 26.0
const BOSS_HP_DECAY := 0.7
## 무한 모드 10·20·30 라운드 보스 체력 배수 (초반 보스도 제한시간의 상당 부분을 버티게). 40 이후는 BOSS_HP_MULT x DECAY^n
const EARLY_BOSS_MULTS := [78.0, 45.0, 9.5]
## 스토리/탑/오늘의 결계 보스 체력 = 라운드 체력 x BOSS_HP_MULT x 이 값 (최종 보스는 x1.5)
const STAGE_BOSS_HP := 0.47
const FINAL_BOSS_TIME := 90.0
const FINAL_BOSS_HP_SCALE := 0.34
const SPAWN_PER_WAVE := 20
const SPAWN_INTERVAL := 0.6
const ENEMY_LIMIT := 100
const COOP_ENEMY_LIMIT := 180
## 협동 보정: 두 전장이 필드 한도를 나눠 쓰고 각자 보스를 잡아야 해서 적을 조금 약하게
const COOP_BOSS_HP := 0.6
const COOP_MOB_HP := 0.8
const BASE_HP := 22.0
const HP_GROWTH := 1.218
## 일반 적은 라운드마다 조금 더 단단해져 중반부터 압박이 쌓인다 (보스 체력에는 적용 안 함)
const MOB_EXTRA_GROWTH := 1.03
## 스토리 장 이어하기: 누적 라운드가 이 값을 넘으면 체력 증가를 조금 누그러뜨림 (대신 보스 방해 기술이 늘어남)
const RUN_SOFT_FROM := 24
const RUN_SOFT := 0.9
## 무한·대전 일반 적 체력 보정 [라운드, 배수] (사이는 선형 보간). 중반(15~30)을 더 빡빡하게, 35~40은 느슨하게
## → 중반에 필드가 차오르는 긴장감, 후반도 압박을 유지하며 최종 보스로. 연장전(41~)은 44라운드까지 다시 1배로 급상승.
## 스토리 스테이지에는 적용 안 함
const MOB_CURVE := [[1, 1.1], [8, 1.6], [14, 2.25], [19, 2.55], [24, 2.45], [28, 1.85], [31, 1.5], [34, 1.05], [37, 0.75], [40, 0.65], [44, 1.1]]
## 무한 모드 난이도: 적 체력·보상 배수, 위기 이벤트 확률
const DIFFICULTIES := [
	{"id": "normal", "name": "보통", "hp": 1.0, "reward": 1.0, "crisis": 0.45, "color": Color(0.35, 0.6, 1.0)},
	{"id": "hard", "name": "어려움", "hp": 1.5, "reward": 1.5, "crisis": 0.6, "color": Color(1.0, 0.6, 0.15)},
	{"id": "hell", "name": "지옥", "hp": 2.2, "reward": 2.2, "crisis": 0.8, "color": Color(0.9, 0.15, 0.2)},
]
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
const SUMMON_PROBS := [0.69, 0.265, 0.04, 0.005]
const LUCK_SHIFT := [-0.0385, 0.025, 0.012, 0.0015]

## 운명 소환: [보석 비용, 성공 확률, 결과 등급]
const GAMBLES := [
	{"name": "영웅 운명 소환", "gems": 1, "chance": 0.6, "rarity": 2},
	{"name": "전설 운명 소환", "gems": 5, "chance": 0.2, "rarity": 3, "pity": 3},
]
## pity: 이만큼 연속 실패하면 다음 번은 확정 (운명의 천장)

## 대전 모드 공격: 적 보내기
## 보내는 사람의 라운드가 높을수록 강해진다 (Board.receive_attack)
const ATTACKS := [
	{"id": "swarm", "name": "잡몹 떼", "gold": 40, "gems": 0, "desc": "빠른 적 떼\n라운드마다 더 많이"},
	{"id": "elite", "name": "정예 괴수", "gold": 150, "gems": 0, "desc": "정예 괴수 (지배 불가)\n12라운드부터 2마리"},
	{"id": "curse", "name": "저주", "gold": 0, "gems": 2, "desc": "상대 공속 -30%\n라운드마다 길게"},
]

# ---------------------------------------------------------------------------
# 대전(pvp) 규칙: 6~9분 안에 승부 (짧은 라운드, 이른 연장 가속)
# ---------------------------------------------------------------------------
const PVP_WAVE_TIME := 14.0
const PVP_BONUS_TIME := 18.0
const PVP_BOSS_TIME := 45.0
const PVP_SPAWN_INTERVAL := 0.5
const PVP_RAMP_FROM := 10          # 이 라운드부터 적 체력이 매 라운드 추가로 늘어난다
const PVP_RAMP := 1.12
const PVP_EXTRA_SPAWN_FROM := 16   # 이 라운드부터 라운드마다 적 +1


## 강화 트랙
const UPGRADES := [
	{"id": "low", "name": "일반/희귀", "rarities": [0, 1], "cur": "gold", "base": 30, "step": 20},
	{"id": "mid", "name": "영웅", "rarities": [2], "cur": "gold", "base": 60, "step": 35},
	{"id": "high", "name": "전설/신화", "rarities": [3, 4], "cur": "gems", "base": 1, "step": 1},
	{"id": "luck", "name": "소환 행운", "rarities": [], "cur": "gold", "base": 100, "step": 100},
]
const UPGRADE_DMG_PER_LEVEL := 0.12

## 랜덤 이벤트 (3, 8, 13, ... 라운드)
const EVENTS := [
	{"id": "goblin", "name": "황금 고블린 출현!", "desc": "잡으면 골드 대박 + 보석"},
	{"id": "lucky", "name": "행운의 시간!", "desc": "15초간 소환 비용 절반"},
	{"id": "frenzy", "name": "광란!", "desc": "이번 라운드 적 이동속도 +30%"},
	{"id": "supply", "name": "보급품 도착!", "desc": "무료 소환 3회"},
	{"id": "storm", "name": "번개 폭풍!", "desc": "필드 모든 적에게 체력 25% 피해"},
	{"id": "gemrain", "name": "보석비!", "desc": "보석 +2"},
]
## 위기 이벤트: 8라운드부터 이벤트 라운드의 약 45%. 버텨내면 라운드 끝에 보석 +2
const CRISES := [
	{"id": "horde", "name": "대침공!!", "desc": "이번 라운드 적이 3배로 몰려옵니다 (대신 약함)"},
	{"id": "rush", "name": "폭주!!", "desc": "10초 동안 모든 적 이동속도 +60%"},
	{"id": "eclipse", "name": "일식!!", "desc": "15초 동안 수호병 사거리 -25%"},
	{"id": "quake", "name": "지진!!", "desc": "수호병 3칸이 3초 동안 기절"},
]
const CRISIS_FROM_WAVE := 8
const CRISIS_CHANCE := 0.45
const CRISIS_REWARD_GEMS := 2

## 피버: 콤보 50·100·150… 달성 시 8초 동안 공속 +30%, 처치 골드 +50%
const FEVER_EVERY := 50
const FEVER_TIME := 8.0
const FEVER_SPEED := 0.3
## 보스를 제한시간 이만큼 남기고 잡으면 "간발의 차" 보너스
const CLUTCH_TIME := 5.0
const CLUTCH_GEMS := 2

## 도전 과제
const MISSIONS := [
	{"id": "first_epic", "name": "첫 영웅", "desc": "영웅 유닛 획득", "gold": 60, "gems": 0},
	{"id": "first_legend", "name": "전설의 시작", "desc": "전설 유닛 획득", "gold": 0, "gems": 2},
	{"id": "first_mythic", "name": "신화 강림", "desc": "신화 유닛 조합", "gold": 300, "gems": 3},
	{"id": "kill_500", "name": "학살자", "desc": "적 500마리 처치", "gold": 200, "gems": 1},
	{"id": "full_board", "name": "만원 사례", "desc": "24칸 이상 채우기", "gold": 150, "gems": 0},
	{"id": "gamble_win3", "name": "운명의 손", "desc": "운명 소환 3회 성공", "gold": 0, "gems": 2},
	{"id": "gamble_lose3", "name": "눈물의 소환", "desc": "운명 소환 3회 연속 실패", "gold": 0, "gems": 3},
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


func mob_curve(wave: int) -> float:
	var last: Array = MOB_CURVE[MOB_CURVE.size() - 1]
	if wave >= int(last[0]):
		return float(last[1])
	for k in range(1, MOB_CURVE.size()):
		var a: Array = MOB_CURVE[k - 1]
		var b: Array = MOB_CURVE[k]
		if wave <= int(b[0]):
			var t := float(wave - int(a[0])) / float(int(b[0]) - int(a[0]))
			return lerpf(float(a[1]), float(b[1]), clampf(t, 0.0, 1.0))
	return 1.0


func wave_hp(wave: int) -> float:
	var hp := BASE_HP * pow(HP_GROWTH, wave - 1)
	# 최종 라운드 이후(대전 연장전)는 더 가파르게 증가
	if wave > FINAL_WAVE:
		hp *= pow(1.12, wave - FINAL_WAVE)
	return hp


## 보스 체력 = 해당 라운드 일반 체력 x 배수 (후반일수록 배수를 낮춰 제한시간 안에 잡을 수 있게)
func boss_hp(wave: int) -> float:
	var n := maxi(wave / 10, 1)
	var hp := wave_hp(wave) * BOSS_HP_MULT * pow(BOSS_HP_DECAY, n - 1)
	if n <= EARLY_BOSS_MULTS.size() and wave != FINAL_WAVE:
		hp = wave_hp(wave) * EARLY_BOSS_MULTS[n - 1]
	if wave == FINAL_WAVE:
		hp *= FINAL_BOSS_HP_SCALE
	return hp


func boss_time(wave: int) -> float:
	return FINAL_BOSS_TIME if wave == FINAL_WAVE else BOSS_WAVE_TIME


## 서버 검증용: 이 모드에서 wave 라운드가 시작될 때까지 걸리는 최소 게임 시간(초) = 준비 시간 + 앞 라운드 타이머 합.
## (라운드 타이머는 보스를 일찍 잡아도 줄지 않는다. 배속 플레이는 벽시계 기준으로 더 짧을 수 있음)
func min_match_time(mode: String, wave: int, stage_rounds := 0) -> float:
	var t := PREP_TIME
	for w in range(1, maxi(wave, 1)):
		if stage_rounds > 0:
			t += BONUS_WAVE_TIME if (w == 5 and stage_rounds >= 8) else WAVE_TIME
		elif is_boss_wave(w):
			t += PVP_BOSS_TIME if mode == "pvp" else boss_time(w)
		elif is_bonus_wave(w):
			t += PVP_BONUS_TIME if mode == "pvp" else BONUS_WAVE_TIME
		else:
			t += PVP_WAVE_TIME if mode == "pvp" else WAVE_TIME
	return t


func is_boss_wave(wave: int) -> bool:
	return wave > 0 and wave % 10 == 0


## 5, 15, 25, 35... 라운드: 제한시간 안에 보물 돼지를 잡는 보너스 라운드
func is_bonus_wave(wave: int) -> bool:
	return wave % 10 == 5


func is_event_wave(wave: int) -> bool:
	return wave % 5 == 3


## 웨이브별 등장 적 구성 (가중치 목록)
## special_wave: 분열체·치유사 해금 기준 라운드 (스토리/탑/오늘의 결계는 장·층에 따라 앞당긴다)
func wave_mix(wave: int, special_wave := -1) -> Array:
	var sw := wave if special_wave < 0 else special_wave
	var mix: Array = [["normal", 10]]
	if wave >= 3:
		mix.append(["fast", 4])
	if wave >= 6:
		mix.append(["tank", 3])
	if wave >= 12:
		mix.append(["shield", 3])
	if sw >= 16:
		mix.append(["splitter", 2])
	if sw >= 22:
		mix.append(["healer", 2])
	return mix


## 스테이지 모드의 분열체·치유사 해금 라운드 보정 (장이 깊을수록, 탑이 높을수록, 악몽일수록 일찍)
func stage_special_offset(chapter: int, tower_floor: int, daily: bool, hard: bool) -> int:
	var off := 0
	if tower_floor > 0:
		off = mini(tower_floor + 4, 24)
	elif daily:
		off = 14
	else:
		off = [0, 0, 3, 6, 10, 13, 16, 18, 20, 22, 24][clampi(chapter, 0, 10)]
	if hard:
		off += 6
	return off


func pick_enemy(rng: RandomNumberGenerator, wave: int, special_wave := -1) -> String:
	var mix := wave_mix(wave, special_wave)
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


func _exit_tree() -> void:
	_theme = null


## 모든 UI 가 공유하는 테마 (버튼 스타일 등)
func ui_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	var f := load("res://fonts/NanumSquareRoundB.ttf")
	if f:
		t.default_font = f
	t.default_font_size = 16
	# 버튼: 두툼한 입체 (모바일 게임 스타일)
	var base := UIKit.NAVY
	var states := {
		"normal": UIKit.bevel(base),
		"hover": UIKit.bevel(base.lightened(0.12)),
		"pressed": UIKit.bevel(base.darkened(0.1), 14, 6, true),
		"disabled": UIKit.bevel(Color(0.2, 0.21, 0.26)),
		"focus": StyleBoxEmpty.new(),
	}
	for s in states:
		# art/ui/button_<상태>.png 가 있으면 이미지 스킨 사용
		var art_sb: StyleBox = Art.stylebox("button_" + s) if s != "focus" else null
		t.set_stylebox(s, "Button", art_sb if art_sb != null else states[s])
	t.set_color("font_outline_color", "Button", UIKit.INK)
	t.set_constant("outline_size", "Button", 4)
	# 글자: 게임 느낌의 테두리
	t.set_color("font_outline_color", "Label", Color(0.03, 0.04, 0.09, 0.9))
	t.set_constant("outline_size", "Label", 3)
	# 패널 / 게이지 / 입력칸 / 목록
	t.set_stylebox("panel", "PanelContainer", UIKit.panel_box())
	var pb_bg := UIKit.inset(Color(0.04, 0.05, 0.1, 0.9), 8)
	pb_bg.set_content_margin_all(0)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = Color(0.35, 0.85, 1.0)
	pb_fill.border_color = Color(1, 1, 1, 0.35)
	pb_fill.border_width_top = 2
	pb_fill.set_corner_radius_all(8)
	t.set_stylebox("fill", "ProgressBar", pb_fill)
	t.set_stylebox("normal", "LineEdit", UIKit.inset())
	t.set_stylebox("focus", "LineEdit", UIKit.inset(Color(0.08, 0.11, 0.22, 0.95)))
	t.set_stylebox("panel", "ItemList", UIKit.inset())
	var sel := StyleBoxFlat.new()
	sel.bg_color = Color(0.3, 0.45, 0.85, 0.6)
	sel.set_corner_radius_all(8)
	t.set_stylebox("selected", "ItemList", sel)
	t.set_stylebox("selected_focus", "ItemList", sel)
	t.set_constant("v_separation", "ItemList", 8)
	t.set_stylebox("normal", "OptionButton", UIKit.bevel(base))
	t.set_stylebox("hover", "OptionButton", UIKit.bevel(base.lightened(0.12)))
	t.set_stylebox("pressed", "OptionButton", UIKit.bevel(base.darkened(0.1), 14, 6, true))
	var tip := UIKit.panel_box(Color(0.06, 0.07, 0.13, 0.96), UIKit.GOLD, 12)
	tip.set_content_margin_all(10)
	tip.shadow_size = 8
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_disabled_color", "Button", Color(0.82, 0.84, 0.9))
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


# ---------------------------------------------------------------------------
# 상점 / 광고 보상 (메타 진행). 대전(pvp)에서는 공정성을 위해 적용하지 않는다.
# ---------------------------------------------------------------------------
const SHOP_ITEMS := [
	{"id": "start_gold", "name": "골드 주머니", "desc": "다음 판 시작 골드 +100", "price": 30, "icon": "gold"},
	{"id": "start_gems", "name": "보석 상자", "desc": "다음 판 시작 보석 +3", "price": 45, "icon": "gem"},
	{"id": "summon_ticket", "name": "소환권 묶음", "desc": "다음 판 무료 소환 5회", "price": 25, "icon": "summon"},
	{"id": "lucky_charm", "name": "행운 부적", "desc": "다음 판 소환 행운 +1", "price": 50, "icon": "luck"},
	{"id": "revive", "name": "부활 깃털", "desc": "패배했을 때 1회 부활 (보유 시 자동 제안)", "price": 90, "icon": "revive"},
]

const PERKS := [
	{"id": "p_gold", "name": "넉넉한 시작", "desc": "시작 골드 +15", "max": 5, "base": 60, "step": 60, "icon": "gold"},
	{"id": "p_chest", "name": "보물 감각", "desc": "보물상자 확률 +20%", "max": 5, "base": 80, "step": 80, "icon": "chest"},
	{"id": "p_gamble", "name": "운명의 별", "desc": "운명 소환 성공률 +2%p", "max": 5, "base": 100, "step": 100, "icon": "gamble"},
	{"id": "p_boss", "name": "보스 사냥꾼", "desc": "보스 제한시간 +3초", "max": 5, "base": 120, "step": 120, "icon": "attack"},
]

const AD_DAILY_LIMIT := 8
const AD_COINS := 40

## 판 보상 코인
func match_coins(wave: int, kills: int, won: bool) -> int:
	return wave * 3 + kills / 25 + (60 if won else 0)


## 인앱 결제 상품 (Google Play Console 의 "인앱 상품" ID 와 같게 등록).
## consumable: 결제 확인 후 소비(consume) → 다시 구매 가능. once: 1회 한정(acknowledge 만)
## price 는 스토어 가격을 못 받아왔을 때 보여줄 표시용 문자열일 뿐, 실제 가격은 스토어가 결정한다.
const IAP_PRODUCTS := [
	{"id": "coins_s", "name": "코인 한 줌", "price": "₩1,200", "icon": "coin", "consumable": true,
		"grant": {"coins": 300}},
	{"id": "coins_m", "name": "코인 자루", "price": "₩5,900", "icon": "coin", "consumable": true, "tag": "+20%",
		"grant": {"coins": 1800}},
	{"id": "coins_l", "name": "코인 금고", "price": "₩12,000", "icon": "coin", "consumable": true, "tag": "+40%",
		"grant": {"coins": 4200}},
	{"id": "starter_pack", "name": "초보자 꾸러미", "price": "₩2,500", "icon": "gift", "once": true, "tag": "1회",
		"grant": {"coins": 800, "items": {"revive": 3, "summon_ticket": 5, "lucky_charm": 2}}},
	{"id": "no_ads", "name": "광고 제거", "price": "₩4,900", "icon": "ad", "once": true,
		"desc": "광고 없이 보상 즉시 받기",
		"grant": {"no_ads": true, "coins": 500}},
]


func iap_product(id: String) -> Dictionary:
	for p in IAP_PRODUCTS:
		if p["id"] == id:
			return p
	return {}


func shop_item(id: String) -> Dictionary:
	for it in SHOP_ITEMS:
		if it["id"] == id:
			return it
	return {}


func perk(id: String) -> Dictionary:
	for p in PERKS:
		if p["id"] == id:
			return p
	return {}


# ---------------------------------------------------------------------------
# 메타 진행: 일일 미션 / 출석 / 유닛 레벨(도감)
# ---------------------------------------------------------------------------
## key: 진행도 이름 (Profile.add_progress 로 누적)
const DAILY_MISSIONS := [
	{"id": "d_play", "key": "play", "goal": 3, "name": "게임 3판", "icon": "play", "coins": 30},
	{"id": "d_kill", "key": "kill", "goal": 1000, "name": "적 1000마리 처치", "icon": "attack", "coins": 40},
	{"id": "d_merge", "key": "merge", "goal": 20, "name": "합성 20회", "icon": "merge", "coins": 30},
	{"id": "d_mythic", "key": "mythic", "goal": 1, "name": "신화 조합 1회", "icon": "recipe", "coins": 50},
	{"id": "d_boss", "key": "boss", "goal": 3, "name": "보스 3마리 처치", "icon": "skull", "coins": 40},
	{"id": "d_ad", "key": "ad", "goal": 1, "name": "광고 1회 보기", "icon": "ad", "coins": 20},
]
const DAILY_ALL_BONUS := 100

## 7일 출석 보상 (코인 또는 아이템)
const ATTENDANCE := [
	{"coins": 50}, {"item": "summon_ticket"}, {"coins": 80}, {"item": "start_gems"},
	{"coins": 100}, {"item": "lucky_charm"}, {"coins": 150, "item": "revive"},
]

const UNIT_MAX_LEVEL := 10
const UNIT_LEVEL_BONUS := 0.05       # 레벨당 공격력 +5%


func unit_level_cost(id: String, level: int) -> int:
	return (UNITS[id]["rarity"] + 1) * 20 * (level + 1)


# ---------------------------------------------------------------------------
# 럭키 슬롯 (게임 중 골드 걸기)
# ---------------------------------------------------------------------------
const SLOT_SYMBOLS := ["gold", "gem", "summon", "star", "skull"]
const SLOT_WEIGHTS := [30, 14, 20, 8, 28]
const SLOT_BETS := [50, 200]
const SLOT_SPIN_TIME := 1.6

# 콤보 / 잭팟
const COMBO_WINDOW := 1.2
const COMBO_STEP := 20
const JACKPOT_CHANCE := 0.004


# ---------------------------------------------------------------------------
# 일일 룰렛 (메뉴): 하루 무료 1회 + 광고 3회
# ---------------------------------------------------------------------------
const ROULETTE := [
	{"coins": 20, "w": 22, "color": Color(0.35, 0.45, 0.75)},
	{"item": "summon_ticket", "w": 14, "color": Color(0.3, 0.7, 0.45)},
	{"coins": 50, "w": 18, "color": Color(0.55, 0.35, 0.8)},
	{"item": "start_gold", "w": 12, "color": Color(0.8, 0.6, 0.2)},
	{"coins": 100, "w": 10, "color": Color(0.35, 0.45, 0.75)},
	{"item": "lucky_charm", "w": 8, "color": Color(0.3, 0.7, 0.45)},
	{"coins": 30, "w": 14, "color": Color(0.55, 0.35, 0.8)},
	{"coins": 500, "w": 2, "color": Color(0.9, 0.2, 0.3), "jackpot": true},
]
const ROULETTE_AD_SPINS := 3


# ---------------------------------------------------------------------------
# 시너지: 서로 다른 유닛 종류 수로 발동 (같은 유닛 여러 마리는 1종)
# ---------------------------------------------------------------------------
const UNIT_TAGS := {
	"sword": ["warrior"], "archer": ["archer"], "mage": ["mage", "fire"], "spear": ["warrior"], "slinger": ["archer", "lightning"],
	"knight": ["warrior"], "sniper": ["archer"], "frost": ["mage", "ice"], "pyro": ["mage", "fire"], "rogue": ["assassin"],
	"storm": ["mage", "lightning"], "berserk": ["warrior"], "alch": ["support"], "bard": ["support"], "ranger": ["archer"],
	"dragoon": ["warrior", "fire"], "archmage": ["mage"], "assassin": ["assassin"], "guardian": ["support", "ice"],
	"phoenix": ["mage", "fire"], "thunder": ["archer", "lightning"], "chrono": ["support", "ice"], "midas": ["assassin"], "reaper": ["assassin", "warrior"],
	"titan": ["warrior"], "paladin": ["warrior", "support"], "plague": ["mage", "support"], "windgod": ["archer"],
	"frostwyrm": ["ice", "fire"], "voidmage": ["mage", "lightning"],
}

## tiers: [필요 종류 수, 수치]
const SYNERGIES := {
	"warrior":   {"name": "전사", "icon": "blade", "color": Color(0.9, 0.55, 0.4), "tiers": [[2, 0.15], [4, 0.35]], "desc": "전사 공격력 +%d%%"},
	"archer":    {"name": "궁수", "icon": "bow", "color": Color(0.5, 0.9, 0.45), "tiers": [[2, 0.12], [4, 0.28]], "desc": "궁수 사거리·공속 +%d%%"},
	"mage":      {"name": "마법사", "icon": "orb", "color": Color(0.6, 0.6, 1.0), "tiers": [[2, 0.2], [4, 0.45]], "desc": "마법사 범위 +%d%%, 스킬 쿨 감소"},
	"assassin":  {"name": "암살", "icon": "dagger", "color": Color(0.7, 0.5, 0.9), "tiers": [[2, 0.1], [3, 0.2]], "desc": "전체 치명타 확률 +%d%%p"},
	"support":   {"name": "지원", "icon": "note", "color": Color(1, 0.6, 0.85), "tiers": [[2, 0.08], [3, 0.15]], "desc": "전체 공속 +%d%%"},
	"fire":      {"name": "불", "icon": "flame", "color": Color(1, 0.45, 0.2), "tiers": [[2, 0.4], [3, 1.0]], "desc": "화상 피해 +%d%%"},
	"ice":       {"name": "얼음", "icon": "snow", "color": Color(0.55, 0.9, 1.0), "tiers": [[2, 0.1], [3, 0.2]], "desc": "공격 시 %d%% 확률 빙결"},
	"lightning": {"name": "번개", "icon": "bolt", "color": Color(1, 0.95, 0.35), "tiers": [[2, 1.0], [3, 3.0]], "desc": "연쇄 +%d, 기절 확률 증가"},
}
const SYNERGY_ORDER := ["warrior", "archer", "mage", "assassin", "support", "fire", "ice", "lightning"]

# ---------------------------------------------------------------------------
# ★ 강화 시도 (칸 단위). 성공률은 점점 낮아지고, ★3 이상 실패 시 하락 위험
# ---------------------------------------------------------------------------
const STAR_MAX := 5
const STAR_CHANCE := [0.85, 0.65, 0.45, 0.3, 0.2]      # ★0→1 ... ★4→5
const STAR_DOWN_CHANCE := [0.0, 0.0, 0.0, 0.35, 0.5]   # 실패 시 한 단계 하락 확률
const STAR_DMG := 0.25            # ★당 공격력 +25%
const STAR_SPEED := 0.10          # ★당 공속 +10%
const AWAKEN_STAR := 3            # ★3 각성: 특성 수치 x1.35, 연쇄/다중 +1
const ENHANCE_TIME := 0.9
const MERGE_GREAT_CHANCE := 0.04  # 합성 대성공 확률 (전설로는 건너뛰지 않음 → 대신 ★1)
## 영웅 3 → 전설 합성 성공 확률. 실패하면 영웅 1개만 남는다. 연속 실패 천장이면 확정
const LEGEND_MERGE_CHANCE := 0.45
const LEGEND_MERGE_PITY := 3

## 소환 보완 (랜덤이지만 억울하지 않게)
const PITY_EPIC := 28      # 영웅 이상이 이만큼 안 나오면 다음 소환 영웅 이상 확정
const PITY_LEGEND := 130   # 전설 확정
const PICK_EVERY := 10     # 10번째 소환마다 3장 중 골라 뽑기
const MERGE_BIAS := 2.0    # 합성 결과: 가까운 신화 조합에 필요한 유닛이 나올 가중치 (+배)


func enhance_cost(rarity: int, star: int) -> int:
	return int((30 + rarity * 40) * pow(1.7, star))


# ---------------------------------------------------------------------------
# 보스 스킬: [스킬 id, 쿨타임]. 시전 준비(cast) 동안 기절시키면 끊긴다.
# ---------------------------------------------------------------------------
## 순서 = Story.BOSS_CHARS (ogre, lich, golem, eye, lord, frost, sand, seraph, nox, void)
## 무한 모드: 10·20·30 라운드 = 0·1·2, 40(최종) = 4, 연장전 50·60… = 5~9, 3 순환
const BOSS_SKILLS := [
	[["dash", 9.0], ["roar", 13.0]],                                   # 0 오우거 대장
	[["summon", 10.0], ["regen", 14.0]],                               # 1 해골 군주
	[["shield", 12.0], ["blast", 11.0]],                               # 2 화염 골렘
	[["blink", 10.0], ["roar", 12.0]],                                 # 3 심연의 눈
	[["dash", 11.0], ["summon", 12.0], ["shield", 14.0], ["blink", 12.0], ["roar", 13.0]],   # 4 사각의 군주 (최종)
	[["frostbite", 11.0], ["roar", 13.0], ["shield", 15.0]],           # 5 서리 여제: 한 줄 빙결
	[["sandstorm", 15.0], ["dash", 10.0], ["summon", 12.0]],           # 6 모래 폭군: 사거리 감소
	[["sanctuary", 13.0], ["regen", 15.0], ["blink", 11.0]],           # 7 세라프: 적 전체 보호막
	[["shadow", 18.0], ["blink", 11.0], ["summon", 13.0], ["dash", 10.0]],   # 8 녹스: 그림자 분신
	[["rift", 12.0], ["summon", 13.0], ["roar", 14.0], ["sanctuary", 15.0], ["frostbite", 16.0], ["blink", 12.0]],   # 9 공허의 왕 (최종)
]
const BOSS_SKILL_NAMES := {"dash": "돌진", "roar": "포효", "summon": "부하 소환", "regen": "재생", "shield": "용암 방패", "blast": "화염 폭발", "blink": "순간이동",
	"frostbite": "서리 감옥", "sandstorm": "모래 폭풍", "sanctuary": "빛의 성역", "shadow": "그림자 분신", "rift": "공허 균열",
	"chill": "냉기 저주", "petrify": "석화의 눈", "weaken": "쇠약 저주", "split": "분열", "greed": "탐욕", "haste": "진군 명령",
	"evade": "환영 걸음"}
## 방해 기술: 뒤로 갈수록(장·라운드·난이도) 보스가 이 중 더 많이 골라 쓰고, 재사용 시간도 짧아진다 (Board._debuff_tier)
##  chill 우리 유닛 공격속도 -35% · petrify 유닛 여러 칸 석화(공격 불가) · weaken 우리 피해 -30%
##  split 보스가 분신 여럿으로 분열 · greed 골드 강탈 · haste 모든 적 이동속도 +60% · evade 모든 적 공격 35% 회피
const DEBUFF_POOL := ["chill", "petrify", "weaken", "split", "evade", "greed", "haste"]
const DEBUFF_MAX := 4
const BOSS_CAST_TIME := 1.0


const UPGRADE_SPD_PER_LEVEL := 0.03    # 등급 강화 1레벨당 공속 +3%
const TRANSCEND_STAR := 5              # ★5 초월: 한 번에 두 번 공격

# ---------------------------------------------------------------------------
# 계정 레벨 / 업적 (영구 성취)
# ---------------------------------------------------------------------------
func xp_to_next(level: int) -> int:
	return 100 + level * 60


func match_xp(wave: int, kills: int, won: bool) -> int:
	return wave * 6 + kills / 8 + (120 if won else 0)


## stat: Profile.life 의 키, goals: 단계별 목표, coins: 단계별 보상
const ACHIEVEMENTS := [
	{"id": "a_kills", "name": "학살자", "icon": "attack", "stat": "kills", "goals": [1000, 10000, 50000], "coins": [50, 200, 600], "desc": "적 %d마리 처치"},
	{"id": "a_mythic", "name": "신화 수집가", "icon": "recipe", "stat": "mythics", "goals": [1, 10, 50], "coins": [80, 250, 800], "desc": "신화 %d회 조합"},
	{"id": "a_star", "name": "장인", "icon": "hammer", "stat": "max_star", "goals": [3, 4, 5], "coins": [60, 150, 400], "desc": "★%d 달성"},
	{"id": "a_round", "name": "생존자", "icon": "heart", "stat": "best_round", "goals": [20, 30, 40], "coins": [50, 120, 300], "desc": "%d라운드 도달"},
	{"id": "a_boss", "name": "보스 사냥꾼", "icon": "skull", "stat": "bosses", "goals": [5, 30, 100], "coins": [60, 200, 500], "desc": "보스 %d마리 처치"},
	{"id": "a_combo", "name": "콤보 마스터", "icon": "bolt", "stat": "max_combo", "goals": [50, 120, 250], "coins": [50, 150, 400], "desc": "%d 콤보 달성"},
	{"id": "a_interrupt", "name": "차단 전문가", "icon": "shield", "stat": "interrupts", "goals": [3, 20, 60], "coins": [60, 180, 450], "desc": "보스 시전 %d회 차단"},
	{"id": "a_jackpot", "name": "잭팟!", "icon": "slot", "stat": "jackpots", "goals": [1, 5, 20], "coins": [80, 200, 500], "desc": "슬롯 잭팟 %d회"},
	{"id": "a_merge", "name": "합성 달인", "icon": "merge", "stat": "merges", "goals": [100, 1000, 5000], "coins": [40, 150, 500], "desc": "합성 %d회"},
	{"id": "a_win", "name": "정복자", "icon": "star", "stat": "wins", "goals": [1, 10, 50], "coins": [100, 300, 1000], "desc": "승리 %d회"},
	{"id": "a_dex", "name": "도감 완성", "icon": "book", "stat": "discovered", "goals": [8, 18, 30], "coins": [50, 150, 500], "desc": "유닛 %d종 수집"},
	{"id": "a_story", "name": "결계 연대기", "icon": "book", "stat": "story_stars", "goals": [30, 90, 135], "coins": [150, 500, 1500], "desc": "스토리 ★ %d개"},
	{"id": "a_hard", "name": "악몽을 걷는 자", "icon": "skull", "stat": "hard_stars", "goals": [15, 60, 135], "coins": [200, 700, 2000], "desc": "악몽 ★ %d개"},
	{"id": "a_tower", "name": "탑의 정복자", "icon": "crown", "stat": "tower", "goals": [10, 30, 60, 100], "coins": [150, 500, 1200, 3000], "desc": "결계의 탑 %d층"},
	{"id": "a_daily", "name": "매일의 수호자", "icon": "clock", "stat": "dailies", "goals": [3, 10, 30], "coins": [100, 300, 1000], "desc": "오늘의 결계 %d회 완료"},
	{"id": "a_control", "name": "지배자", "icon": "curse", "stat": "controls", "goals": [5, 30, 100], "coins": [60, 200, 600], "desc": "지배 %d회"},
]

class_name Story
extends RefCounted
## 스토리 모드 데이터: 등장인물, 5장 20스테이지, 대사.
## 대사의 {player} 는 닉네임으로 바뀐다. 초상화 이미지: art/portraits/<인물 id>.png

const CHARACTERS := {
	"arka":   {"name": "아르카", "title": "노현자", "glyph": "orb", "color": Color(0.55, 0.8, 1.0)},
	"rina":   {"name": "리나", "title": "숲의 궁수", "glyph": "bow", "color": Color(0.5, 0.95, 0.55)},
	"kael":   {"name": "카엘", "title": "라이벌 결계사", "glyph": "blade", "color": Color(1, 0.45, 0.4)},
	"lord":   {"name": "사각의 군주", "title": "초대 수호자", "glyph": "crown", "color": Color(0.75, 0.4, 1.0)},
	"ogre":   {"name": "오우거 대장", "title": "변방의 약탈자", "glyph": "axe", "color": Color(0.9, 0.5, 0.3)},
	"lich":   {"name": "해골 군주", "title": "망자의 왕", "glyph": "skull", "color": Color(0.8, 0.8, 0.85)},
	"golem":  {"name": "화염 골렘", "title": "광산의 심장", "glyph": "flame", "color": Color(1, 0.45, 0.15)},
	"eye":    {"name": "심연의 눈", "title": "틈의 감시자", "glyph": "scope", "color": Color(0.6, 0.3, 0.9)},
	"narr":   {"name": "", "title": "", "glyph": "book", "color": Color(0.7, 0.72, 0.8)},
}

## hp: 적 체력 배수, gold: 시작 골드, boss: 보스 세트 (0~3, 4 = 최종), mods: 스테이지 규칙
const CHAPTERS := [
	{"id": 1, "name": "변방 마을 에르카", "color": Color(0.45, 0.8, 0.45), "hp": 2.0, "gold": 120, "gems": 2,
		"desc": "결계의 가장 바깥, 괴물들이 처음 모습을 드러낸 곳.",
		"stages": [
			{"name": "첫 번째 결계", "rounds": 6, "mods": [], "intro": [
				["narr", "사각 왕국 콰드라. 이 땅은 초대 수호자가 세운 '사각 결계'로 천 년을 버텨왔다."],
				["narr", "심연에서 온 괴물들은 결계의 틈을 찾아 테두리를 끝없이 맴돈다. 너무 많이 쌓이면... 결계는 깨진다."],
				["arka", "{player}, 오늘부터 너는 결계사다. 결계 안쪽 칸에 수호병을 불러내 괴물을 막아라."],
				["arka", "같은 수호병 셋이 모이면 더 강한 자로 합쳐진다. 기억해 두거라."]],
			 "outro": [["arka", "첫 결계치고는 나쁘지 않구나. 하지만 밤이 되면 놈들은 더 빨라진다."]]},
			{"name": "밤의 습격", "rounds": 8, "mods": ["fast"], "intro": [
				["rina", "당신이 새로 온 결계사? 난 리나. 이 숲 근처를 지키고 있어."],
				["rina", "오늘 밤 놈들이 유난히 빨라. 사거리 짧은 수호병은 테두리 가까이 두는 게 좋아!"]]},
			{"name": "마을 광장", "rounds": 10, "mods": ["rich"], "intro": [
				["arka", "마을 사람들이 금화를 모아 주었다. 소환과 강화에 아낌없이 쓰거라."],
				["rina", "★ 강화는 도박이야. 실패해도 울지 말고!"]]},
			{"name": "오우거 대장", "rounds": 10, "mods": [], "boss": 0, "intro": [
				["ogre", "크하하! 이 얇은 네모 따위가 날 막겠다고?"],
				["arka", "저 녀석은 돌진하고 포효한다. 포효를 맞으면 수호병이 잠시 굳어버리지."],
				["arka", "빨간 원이 보이면 기절시켜라! 시전을 끊을 수 있다."]],
			 "outro": [
				["ogre", "크윽... 이 결계... 예전보다... 단단해...?"],
				["arka", "예전보다? ...이상하군. 놈들은 결계를 '알고' 있는 것 같다."],
				["rina", "숲 쪽이 조용해졌어. 너무 조용해. 망자의 숲으로 가 보자."]]},
		]},
	{"id": 2, "name": "망자의 숲", "color": Color(0.6, 0.75, 0.7), "hp": 4.2, "gold": 220, "gems": 3,
		"desc": "쓰러진 수호자들이 잠든 숲. 뼈들이 다시 일어나고 있다.",
		"stages": [
			{"name": "안개 낀 길", "rounds": 8, "mods": ["armored"], "intro": [
				["rina", "여긴 옛 수호자들의 무덤이야. 어째서 뼈들이 움직이지...?"],
				["arka", "단단한 뼈 갑옷이다. 창병과 연금술사로 방어를 깎아라."]]},
			{"name": "뼈의 행렬", "rounds": 10, "mods": ["swarm"], "intro": [
				["rina", "끝이 없어! 수가 너무 많아!"],
				["arka", "범위 공격이다. 마법사를 여럿 모으면 '마법사 시너지'로 폭발이 커진다."]]},
			{"name": "리나의 결의", "rounds": 10, "mods": [], "intro": [
				["rina", "우리 아버지도 수호자였어. 이 숲 어딘가에 잠들어 계셔."],
				["rina", "{player}, 끝까지 같이 가 줄 거지? ...대답은 결계로 해."]]},
			{"name": "해골 군주", "rounds": 10, "mods": ["armored"], "boss": 1, "intro": [
				["lich", "살아있는 자가 결계를 지킨다고? 우리도 한때는 그랬지."],
				["lich", "보아라, 결계에 갇힌 우리의 영혼을. 이것이 네 미래다."],
				["arka", "부하를 부르고 스스로 회복한다. 빠르게 몰아쳐라!"]],
			 "outro": [
				["lich", "결계는... 우리를... 가두었다... 그분이 말씀하셨지... 모두 풀어주겠다고..."],
				["rina", "그분? 누굴 말하는 거야?"],
				["arka", "......초대 수호자. 설마, 그자가 살아 있단 말인가."]]},
		]},
	{"id": 3, "name": "불타는 광산", "color": Color(1, 0.55, 0.3), "hp": 7.2, "gold": 330, "gems": 4,
		"desc": "결계석을 캐던 광산. 지금은 용암과 골렘이 차지했다.",
		"stages": [
			{"name": "용암 갱도", "rounds": 10, "mods": ["tank"], "intro": [
				["arka", "결계석은 이 광산에서 나온다. 여기가 무너지면 새 결계를 세울 수 없다."],
				["arka", "무거운 놈들이다. 넉백으로 밀어내고 저격수로 관통시켜라."]]},
			{"name": "광부들의 비명", "rounds": 10, "mods": ["fast", "rich"], "intro": [
				["rina", "광부들이 금을 남기고 도망쳤어. 이걸로 슬롯이라도 돌려볼까?"],
				["arka", "...잭팟이 나오면 나도 한 번 돌려보마."]]},
			{"name": "카엘의 도전", "rounds": 10, "mods": ["armored"], "intro": [
				["kael", "네가 요즘 소문난 결계사냐? 흥, 운이 좋았을 뿐이겠지."],
				["kael", "이 갱도는 내가 맡는다. 너보다 오래 버티는 걸 보여주지."],
				["rina", "...저 사람 대전 모드에서 만나면 혼내줘."]]},
			{"name": "화염 골렘", "rounds": 10, "mods": ["tank"], "boss": 2, "intro": [
				["golem", "......결계석......내 심장......돌려받는다......"],
				["arka", "용암 방패를 두르면 피해가 크게 줄어든다. 방패가 꺼질 때를 노려라!"]],
			 "outro": [
				["kael", "...인정하지. 네 결계는 진짜다."],
				["kael", "하지만 알아둬. 심연의 문이 열렸다. 거긴 나도 무서워."],
				["arka", "문 너머에서 초대 수호자의 목소리가 들린다는 소문이 있다. 가자."]]},
		]},
	{"id": 4, "name": "심연의 문", "color": Color(0.6, 0.4, 0.95), "hp": 11.0, "gold": 450, "gems": 5,
		"desc": "결계에 생긴 가장 큰 틈. 이곳에서 모든 괴물이 흘러나온다.",
		"stages": [
			{"name": "균열", "rounds": 10, "mods": ["swarm", "fast"], "intro": [
				["narr", "하늘이 사각형으로 갈라져 있다. 그 틈에서 끝없는 눈동자들이 이쪽을 본다."],
				["rina", "{player}, 무서워도... 칸은 채워야 해."]]},
			{"name": "뒤틀린 결계", "rounds": 10, "mods": ["no_gamble"], "intro": [
				["arka", "이곳에선 운이 통하지 않는다. 도박도 막혀 있지. 오직 실력뿐이다."],
				["kael", "드디어 공평한 싸움이군."]]},
			{"name": "마지막 방어선", "rounds": 12, "mods": ["armored", "tank"], "intro": [
				["kael", "여기가 뚫리면 왕도까지 막을 게 없다. 너, 내 등 뒤를 맡아라."],
				["rina", "셋이서라면 할 수 있어!"]]},
			{"name": "심연의 눈", "rounds": 10, "mods": ["fast"], "boss": 3, "intro": [
				["eye", "보인다. 보인다. 네 결계의 모든 틈이."],
				["arka", "순간이동을 한다! 트랙 어디서든 나타날 수 있으니 결계 전체를 고르게 채워라."]],
			 "outro": [
				["eye", "그분이... 기다리신다... 무너진 왕도에서..."],
				["lord", "(멀리서) 잘 왔다, 어린 결계사여. 천 년 만의 손님이구나."],
				["arka", "......틀림없다. 저 목소리는 초대 수호자, 나의 스승이다."]]},
		]},
	{"id": 5, "name": "무너진 왕도", "color": Color(0.95, 0.35, 0.5), "hp": 15.5, "gold": 600, "gems": 6,
		"desc": "천 년 전 첫 결계가 세워진 곳. 모든 것이 시작되고, 끝나는 곳.",
		"stages": [
			{"name": "잿빛 성문", "rounds": 10, "mods": ["fast", "armored"], "intro": [
				["lord", "결계는 괴물만 가둔 것이 아니다. 쓰러진 수호자의 영혼도 함께 가두었지."],
				["lord", "나는 그들을 풀어주려는 것뿐이다. 결계를 모두 부숴서."]]},
			{"name": "초대 수호자의 기록", "rounds": 12, "mods": ["swarm"], "intro": [
				["narr", "벽에 새겨진 기록: '결계는 영원할 수 없다. 다음 결계사가 새 결계를 세워야 한다.'"],
				["arka", "스승님은... 후계자를 기다리신 거였군. 결계를 '새로 세울' 누군가를."],
				["rina", "그게 {player}야!"]]},
			{"name": "모두의 결계", "rounds": 12, "mods": ["rich", "tank"], "intro": [
				["kael", "마지막이다. 가진 걸 전부 쏟아부어."],
				["arka", "신화의 수호자들을 불러라. 불사조, 뇌신, 시간술사, 황금왕, 그림자군주. 그들이 너를 기다린다."]]},
			{"name": "사각의 군주", "rounds": 12, "mods": [], "boss": 4, "intro": [
				["lord", "보여다오, 후계자여. 네 결계가 나의 것보다 단단한지."],
				["lord", "나를 넘어선다면... 새 결계의 주인은 네가 된다."],
				["arka", "모든 기술을 쓴다. 체력이 절반이 되면 광폭해진다. {player}, 네 모든 걸 걸어라!"]],
			 "outro": [
				["lord", "......훌륭하다. 천 년 동안 기다린 보람이 있구나."],
				["lord", "갇힌 영혼들은 이제 새 결계와 함께 쉴 수 있겠지. 고맙다, 후계자여."],
				["narr", "그날, 콰드라의 하늘에 새로운 사각형이 떠올랐다. 이전보다 더 밝고 단단한."],
				["rina", "끝난 거야? ...아니, 이제 시작이지. 다음 결계사는 {player}니까!"],
				["narr", "- 1부 완결. 무한 모드와 대전에서 결계를 계속 지켜주세요 -"]]},
		]},
]

const MOD_INFO := {
	"fast": {"name": "질주", "icon": "speed", "desc": "적 이동속도 +25%"},
	"armored": {"name": "철갑", "icon": "shield", "desc": "적 방어력 +15"},
	"rich": {"name": "풍요", "icon": "gold", "desc": "처치 골드 +50%"},
	"swarm": {"name": "대군", "icon": "swarm", "desc": "적 수 +50%, 체력 -25%"},
	"tank": {"name": "중장갑", "icon": "elite", "desc": "탱커 출현 증가"},
	"no_gamble": {"name": "운 봉인", "icon": "lock", "desc": "도박·슬롯 사용 불가"},
}

## 장별 ★ 상자: [필요 ★, 코인, 아이템]
const CHEST_STEPS := [[4, 100, "summon_ticket"], [8, 200, "lucky_charm"], [12, 400, "revive"]]
const BOSS_NAMES := ["오우거 대장", "해골 군주", "화염 골렘", "심연의 눈", "사각의 군주"]


static func stage_id(ch: int, st: int) -> String:
	return "%d-%d" % [ch, st]


static func get_stage(id: String) -> Dictionary:
	## {chapter, index, data} 또는 {}
	var parts := id.split("-")
	if parts.size() != 2:
		return {}
	var ci := int(parts[0]) - 1
	var si := int(parts[1]) - 1
	if ci < 0 or ci >= CHAPTERS.size() or si < 0 or si >= CHAPTERS[ci]["stages"].size():
		return {}
	return {"chapter": CHAPTERS[ci], "index": si, "data": CHAPTERS[ci]["stages"][si], "id": id}


static func next_stage(id: String) -> String:
	var parts := id.split("-")
	var ci := int(parts[0])
	var si := int(parts[1])
	if si < CHAPTERS[ci - 1]["stages"].size():
		return stage_id(ci, si + 1)
	if ci < CHAPTERS.size():
		return stage_id(ci + 1, 1)
	return ""


static func all_ids() -> Array:
	var out: Array = []
	for ch in CHAPTERS:
		for i in ch["stages"].size():
			out.append(stage_id(ch["id"], i + 1))
	return out

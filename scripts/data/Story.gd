class_name Story
extends RefCounted
## 스토리 모드 데이터: 등장인물, 1부(1~5장) + 2부(6~10장) 45스테이지, 대사.
## 반복 콘텐츠: 악몽 난이도(H 접두), 결계의 탑(T층), 오늘의 결계(D날짜) - 모두 get_stage 로 만들어진다.
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
	"mira":   {"name": "미라", "title": "심연의 무녀", "glyph": "halo", "color": Color(0.85, 0.5, 1.0)},
	"frost":  {"name": "서리 여제", "title": "북방의 지배자", "glyph": "snow", "color": Color(0.6, 0.9, 1.0)},
	"sand":   {"name": "모래 폭군", "title": "사막의 왕", "glyph": "meteor", "color": Color(1, 0.8, 0.4)},
	"seraph": {"name": "세라프", "title": "타락한 천사", "glyph": "wing", "color": Color(1, 0.95, 0.7)},
	"nox":    {"name": "녹스", "title": "그림자 쌍둥이", "glyph": "skull", "color": Color(0.55, 0.45, 0.75)},
	"void":   {"name": "공허의 왕", "title": "모든 틈의 주인", "glyph": "crown", "color": Color(0.5, 0.2, 0.7)},
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
	# ======================= 2부: 새 결계의 주인 =======================
	{"id": 6, "name": "얼어붙은 북방", "color": Color(0.55, 0.85, 1.0), "hp": 21.0, "gold": 700, "gems": 6,
		"desc": "새 결계가 세워진 지 한 달. 북쪽 끝에서 결계가 얼어붙기 시작했다.",
		"stages": [
			{"name": "서리 전령", "rounds": 10, "mods": ["fast"], "intro": [
				["narr", "- 2부: 새 결계의 주인 -"],
				["narr", "새 결계가 떠오른 지 한 달. 콰드라에 평화가 오는 듯했다."],
				["rina", "{player}! 북쪽 결계가 하얗게 얼었대. 괴물들이 얼음을 타고 미끄러져 와!"],
				["arka", "새 결계는 아직 어리다. 주인인 네가 직접 지켜야 단단해진다."]]},
			{"name": "눈보라 고개", "rounds": 10, "mods": ["armored", "heroes"], "intro": [
				["kael", "늦었군. 여긴 적 영웅들이 떼로 몰려와. 도적 놈은 골드를 훔쳐 가니 먼저 잡아."],
				["rina", "카엘! 너도 와 준 거야?"],
				["kael", "착각하지 마. 네가 무너지면 내 결계도 무너지니까."]]},
			{"name": "얼음 감옥", "rounds": 12, "mods": ["midboss", "tank"], "intro": [
				["narr", "얼음 속에 갇힌 옛 결계사들이 보인다. 모두 눈을 뜬 채였다."],
				["mira", "(얼음 너머에서) 불쌍하지? 결계를 지키다 결계에 갇힌 사람들이야."],
				["rina", "누구야?!"]]},
			{"name": "무녀의 속삭임", "rounds": 12, "mods": ["curse"], "intro": [
				["mira", "난 미라. 심연의 무녀. 결계 너머의 목소리를 듣는 사람."],
				["mira", "{player}, 네 결계가 무엇을 가두는지 알아? 괴물만이 아니야."],
				["arka", "귀 기울이지 마라. 저주가 수호병을 느리게 만든다."]]},
			{"name": "서리 여제", "rounds": 12, "mods": ["fast", "armored"], "boss": 5, "intro": [
				["frost", "따뜻한 피를 가진 결계사... 너도 얼음 조각상이 되어라."],
				["arka", "포효로 수호병을 굳히고 방패를 두른다. 방패가 꺼질 때를 노려라!"]],
			 "outro": [
				["frost", "나는... 그저... 추운 게 싫었을 뿐인데... 심연이 따뜻하다고... 했어..."],
				["mira", "여제는 내 첫 번째 제자였어. 심연은 약속을 지키거든. 곧 알게 될 거야."],
				["kael", "저 무녀, 쫓아가자. 남쪽 사막으로 사라졌어."]]},
		]},
	{"id": 7, "name": "사막의 신기루", "color": Color(1, 0.8, 0.4), "hp": 28.0, "gold": 800, "gems": 7,
		"desc": "모래 폭풍 속에 결계의 사본이 떠 있다. 무엇이 진짜 결계인가.",
		"stages": [
			{"name": "모래 폭풍", "rounds": 10, "mods": ["swarm", "fast"], "intro": [
				["rina", "눈이 따가워! 결계가... 두 개로 보여."],
				["arka", "신기루다. 가짜 결계에 속지 말고 네 칸을 믿어라."]]},
			{"name": "상인의 오아시스", "rounds": 12, "mods": ["rich", "elites"], "intro": [
				["narr", "사막 한가운데 오아시스. 떠돌이 상인이 금화 자루를 흔든다."],
				["rina", "정예 괴수를 잡을 때마다 금화를 준대! ...장사꾼 냄새가 나지만."]]},
			{"name": "가난한 결계", "rounds": 12, "mods": ["poor", "heroes"], "intro": [
				["kael", "상인이 사라졌다. 금화도 함께. 이제 가진 걸로 버텨야 해."],
				["arka", "골드가 부족할 땐 지배를 써라. 적의 영웅을 빼앗아 우리 편으로 만드는 거다."]]},
			{"name": "모래 속의 왕도", "rounds": 12, "mods": ["midboss", "armored"], "intro": [
				["narr", "모래 아래에서 또 하나의 왕도가 떠오른다. 사각형이 아닌, 원형의 결계."],
				["mira", "옛날엔 원형 결계도 있었어. 사각의 군주가 부숴버렸지. 네 스승의 스승이 말이야."],
				["arka", "...그런 기록은 없다."],
				["mira", "기록은 이긴 사람이 쓰는 거니까."]]},
			{"name": "모래 폭군", "rounds": 12, "mods": ["swarm"], "boss": 6, "intro": [
				["sand", "원형 결계의 마지막 수호자다. 네모난 결계 따위, 모래로 덮어주마!"],
				["arka", "돌진과 부하 소환. 끝없이 불러낸다. 범위 공격을 준비해라!"]],
			 "outro": [
				["sand", "우리도... 지키려 했다... 사각의 군주가... 모든 걸 빼앗기 전까지..."],
				["rina", "{player}... 우리가 믿던 결계가 정말 옳은 걸까?"],
				["kael", "옳든 아니든, 저 괴물들이 마을을 덮치는 건 막아야 해. 그게 결계사다."],
				["mira", "하늘을 봐. 에테르 섬이 떨어지고 있어. 천사가 울고 있거든."]]},
		]},
	{"id": 8, "name": "하늘 섬 에테르", "color": Color(0.95, 0.95, 0.7), "hp": 36.0, "gold": 900, "gems": 8,
		"desc": "결계를 하늘에서 지켜보던 천사들의 섬. 그 섬이 추락하고 있다.",
		"stages": [
			{"name": "추락하는 섬", "rounds": 12, "mods": ["fast", "heroes"], "intro": [
				["narr", "구름 위, 부서진 사각형의 섬들이 하나둘 떨어진다."],
				["rina", "여기서 싸우면 떨어지는 거 아냐?!"],
				["arka", "떨어지기 전에 끝내면 된다."]]},
			{"name": "천사의 무덤", "rounds": 12, "mods": ["armored", "midboss"], "intro": [
				["narr", "날개가 꺾인 천사 석상들. 모두 사각형 결계를 향해 기도하는 자세다."],
				["kael", "천사들도 결계를 지켰던 거야. 하지만 왜 다 쓰러져 있지?"]]},
			{"name": "카엘의 비밀", "rounds": 12, "mods": ["curse", "tank"], "intro": [
				["kael", "...말할 게 있어. 나, 원래 심연 쪽 사람이었어."],
				["kael", "미라가 날 키웠지. 결계를 부수라고. 하지만 너랑 싸우면서... 지키고 싶어졌어."],
				["rina", "그래서 처음에 그렇게 까칠했구나?"],
				["kael", "...시끄러워. 적이나 막아."]]},
			{"name": "빛의 제단", "rounds": 12, "mods": ["elites", "heroes"], "intro": [
				["seraph", "(제단 위에서) 결계사여, 너희가 만든 벽이 우리의 하늘을 잘랐다."],
				["arka", "세라프... 결계의 수호천사였던 자가 어째서..."]]},
			{"name": "타락 천사 세라프", "rounds": 12, "mods": ["fast", "armored"], "boss": 7, "intro": [
				["seraph", "빛은 경계를 모른다. 너의 네모난 감옥을 녹여주마."],
				["arka", "재생하고 순간이동한다. 체력이 차오르기 전에 몰아쳐라!"]],
			 "outro": [
				["seraph", "용서해다오... 심연은... 결계가 없는 세상을... 약속했다..."],
				["mira", "다들 같은 말을 하지? 결계가 없으면 행복할 거라고. 그걸 믿게 하는 게 내 일이야."],
				["kael", "미라! 이제 그만해!"],
				["mira", "그만할 수 없어, 카엘. 그분이 깨어나고 있거든. 그림자 미궁에서 기다릴게."]]},
		]},
	{"id": 9, "name": "그림자 미궁", "color": Color(0.55, 0.45, 0.8), "hp": 46.0, "gold": 1000, "gems": 9,
		"desc": "결계의 그림자로 만들어진 미궁. 같은 길이 끝없이 반복된다.",
		"stages": [
			{"name": "거울 복도", "rounds": 12, "mods": ["swarm", "curse"], "intro": [
				["narr", "사방이 거울. 거울 속의 {player}가 다른 방향으로 수호병을 배치하고 있다."],
				["rina", "저건... 우리야? 우리랑 똑같이 싸우는데 반대로 움직여."]]},
			{"name": "쌍둥이의 장난", "rounds": 12, "mods": ["heroes", "poor"], "intro": [
				["nox", "(두 목소리가 겹친다) 안녕, 결계사. 우린 녹스. 둘이지만 하나."],
				["nox", "너희가 버린 그림자로 태어났어. 결계가 빛을 가두면, 그림자는 우리가 가져가지."]]},
			{"name": "잃어버린 기억", "rounds": 12, "mods": ["midboss", "elites"], "intro": [
				["arka", "...이곳을 안다. 천 년 전, 스승님과 함께 이 미궁을 봉인했다."],
				["arka", "스승님은 말씀하셨지. '결계는 벽이 아니라 약속이다. 지키는 사람이 사라지면 결계도 사라진다.'"],
				["rina", "그러니까 {player}가 있는 한, 결계는 안 사라지는 거지!"]]},
			{"name": "미라의 선택", "rounds": 12, "mods": ["fast", "armored", "heroes"], "intro": [
				["mira", "카엘. 돌아와. 넌 원래 우리 쪽이잖아."],
				["kael", "난 이제 결계사야. {player}의 동료고."],
				["mira", "...그래. 그럼 너희 모두, 그분 앞에서 무릎 꿇게 될 거야."]]},
			{"name": "그림자 쌍둥이 녹스", "rounds": 12, "mods": ["swarm", "curse"], "boss": 8, "intro": [
				["nox", "우리를 둘 다 잡을 수 있을까? 하나가 사라지면 하나가 나타나거든."],
				["arka", "순간이동과 소환, 돌진까지. 결계 전체를 고르게 채워 어디서 나타나도 막아라!"]],
			 "outro": [
				["nox", "빛도... 그림자도... 결국 같은 결계 안에 있었네..."],
				["mira", "(무너지며) 그분이... 깨어났어. 공허의 왕좌가 열렸어..."],
				["mira", "{player}... 미안. 나도... 결계 안에서... 살고 싶었어..."],
				["kael", "미라!!"],
				["arka", "공허의 왕. 모든 틈의 주인. 천 년 전 스승님도 이기지 못하고 봉인만 했던 존재다."]]},
		]},
	{"id": 10, "name": "공허의 왕좌", "color": Color(0.6, 0.25, 0.85), "hp": 58.0, "gold": 1200, "gems": 10,
		"desc": "모든 결계의 바깥. 틈과 틈이 만나는 곳, 공허의 왕이 앉아 있다.",
		"stages": [
			{"name": "틈의 바다", "rounds": 12, "mods": ["fast", "swarm", "heroes"], "intro": [
				["narr", "발밑이 없다. 오직 {player}의 결계만이 공허 위에 떠 있다."],
				["rina", "무서워. 그래도 칸은 채워야지. 그렇지?"]]},
			{"name": "마지막 동료들", "rounds": 12, "mods": ["rich", "midboss", "elites"], "intro": [
				["frost", "(얼음 조각이 빛난다) ...결계사. 이번엔 너를 도우러 왔다."],
				["sand", "원형이든 사각이든 상관없다. 공허만은 막아야지."],
				["seraph", "천사의 빛을 네 결계에 보탠다."],
				["kael", "봐, {player}. 네가 이긴 녀석들이 다 네 편이 됐어."]]},
			{"name": "무너지는 세계", "rounds": 14, "mods": ["armored", "tank", "curse"], "intro": [
				["arka", "공허가 콰드라를 삼키고 있다. 이 결계가 마지막 방패다."],
				["arka", "{player}, 스승님이 남긴 마지막 가르침을 전한다. 결계는 혼자 세우는 게 아니다."]]},
			{"name": "새벽의 결계", "rounds": 14, "mods": ["heroes", "elites", "fast"], "intro": [
				["mira", "(희미한 빛으로) ...{player}. 공허의 왕은 결계 안의 '두려움'을 먹고 자라."],
				["mira", "두려워하지 마. 네 결계는... 따뜻했어."],
				["rina", "미라...!"]]},
			{"name": "공허의 왕", "rounds": 14, "mods": ["armored"], "boss": 9, "intro": [
				["void", "......작은 사각형. 천 년 전의 그자와 같은 모양이군."],
				["void", "모든 결계는 언젠가 깨진다. 나는 그 틈이다. 나는 끝이다."],
				["arka", "모든 기술을 쓴다. 체력이 절반이 되면 광폭해진다. 모두의 힘을 모아라!"],
				["kael", "{player}! 우리가 여기 있어!"]],
			 "outro": [
				["void", "......끝이... 아니라고...? 틈이... 메워진다..."],
				["narr", "그날, 공허의 바다 위에 수많은 사각형이 떠올랐다. 모두가 함께 세운 결계였다."],
				["arka", "스승님, 보고 계십니까. 결계는 이제 벽이 아니라, 약속이 되었습니다."],
				["kael", "...고마워, {player}. 미라도 어딘가에서 웃고 있을 거야."],
				["rina", "우리 결계, 앞으로도 같이 지키자!"],
				["narr", "- 2부 완결. 악몽 난이도·결계의 탑·오늘의 결계에서 끝없는 도전이 기다립니다 -"]]},
		]},
]

const MOD_INFO := {
	"fast": {"name": "질주", "icon": "speed", "desc": "적 이동속도 +25%"},
	"armored": {"name": "철갑", "icon": "shield", "desc": "적 방어력 +15"},
	"rich": {"name": "풍요", "icon": "gold", "desc": "처치 골드 +50%"},
	"swarm": {"name": "대군", "icon": "swarm", "desc": "적 수 +50%, 체력 -25%"},
	"tank": {"name": "중장갑", "icon": "elite", "desc": "탱커 출현 증가"},
	"no_gamble": {"name": "운 봉인", "icon": "lock", "desc": "도박·슬롯 사용 불가"},
	"heroes": {"name": "영웅 습격", "icon": "attack", "desc": "라운드마다 적 영웅 난입"},
	"elites": {"name": "정예", "icon": "elite", "desc": "정예 괴수 자주 등장"},
	"poor": {"name": "빈곤", "icon": "gold", "desc": "시작·처치 골드 -30%"},
	"curse": {"name": "저주", "icon": "curse", "desc": "수호병 공격속도 -15%"},
	"midboss": {"name": "중간보스", "icon": "skull", "desc": "4·8라운드에 중간보스"},
}

## 장별 ★ 상자: [필요 ★, 코인, 아이템]
const CHEST_STEPS := [[4, 100, "summon_ticket"], [8, 200, "lucky_charm"], [12, 400, "revive"]]
const BOSS_NAMES := ["오우거 대장", "해골 군주", "화염 골렘", "심연의 눈", "사각의 군주", "서리 여제", "모래 폭군", "타락 천사 세라프", "그림자 쌍둥이 녹스", "공허의 왕"]
const BOSS_CHARS := ["ogre", "lich", "golem", "eye", "lord", "frost", "sand", "seraph", "nox", "void"]
const FINAL_BOSSES := [4, 9]     # 1부·2부 최종 보스 (2페이즈, 제한시간 75초)

## 반복 콘텐츠
const HARD_HP := 1.9             # 악몽: 적 체력 배수
const HARD_REWARD := 1.6         # 악몽: 보상 배수
const MOD_POOL := ["fast", "armored", "rich", "swarm", "tank", "heroes", "elites", "poor", "curse", "midboss"]


static func stage_id(ch: int, st: int) -> String:
	return "%d-%d" % [ch, st]


static func get_stage(id: String) -> Dictionary:
	## {chapter, index, data, id} 또는 {}. H<장-단계> = 악몽, T<층> = 결계의 탑, D<YYYYMMDD> = 오늘의 결계
	if id.begins_with("H"):
		var base := get_stage(id.substr(1))
		if base.is_empty():
			return {}
		var ch: Dictionary = base["chapter"].duplicate()
		ch["hp"] = float(ch["hp"]) * HARD_HP
		ch["gold"] = int(ch["gold"] * 1.1)
		var d: Dictionary = base["data"].duplicate()
		d["name"] = "악몽 · " + d["name"]
		d["intro"] = []
		d["outro"] = []
		var mods: Array = d.get("mods", []).duplicate()
		for extra in ["heroes", "midboss"]:
			if not extra in mods and mods.size() < 3:
				mods.append(extra)
		d["mods"] = mods
		return {"chapter": ch, "index": base["index"], "data": d, "id": id, "hard": true}
	if id.begins_with("T"):
		var n := int(id.substr(1))
		return {} if n < 1 else tower_stage(n)
	if id.begins_with("D"):
		return {} if id.length() != 9 else daily_stage(id)
	var parts := id.split("-")
	if parts.size() != 2:
		return {}
	var ci := int(parts[0]) - 1
	var si := int(parts[1]) - 1
	if ci < 0 or ci >= CHAPTERS.size() or si < 0 or si >= CHAPTERS[ci]["stages"].size():
		return {}
	return {"chapter": CHAPTERS[ci], "index": si, "data": CHAPTERS[ci]["stages"][si], "id": id}


static func next_stage(id: String) -> String:
	if id.begins_with("H"):
		var nb := next_stage(id.substr(1))
		return "" if nb == "" else "H" + nb
	if id.begins_with("T"):
		return "T%d" % (int(id.substr(1)) + 1)
	if id.begins_with("D"):
		return ""
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


static func hard_ids() -> Array:
	var out: Array = []
	for id in all_ids():
		out.append("H" + id)
	return out


static func chapter_of(id: String) -> int:
	## 스테이지의 장 번호 (탑/오늘의 결계는 0)
	if id.begins_with("T") or id.begins_with("D"):
		return 0
	return int(id.trim_prefix("H").split("-")[0])


static func _random_mods(rng: RandomNumberGenerator, n: int) -> Array:
	var pool := MOD_POOL.duplicate()
	var out: Array = []
	while out.size() < n and not pool.is_empty():
		var m: String = pool[rng.randi() % pool.size()]
		pool.erase(m)
		if (m == "rich" and "poor" in out) or (m == "poor" and "rich" in out):
			continue
		out.append(m)
	return out


static func tower_stage(n: int) -> Dictionary:
	## 결계의 탑 n층: 층마다 적이 약 13%씩 강해지고, 규칙이 무작위로 붙는다 (끝없음)
	var rng := RandomNumberGenerator.new()
	rng.seed = n * 7919 + 17
	var mod_n := 0 if n < 3 else (1 if n < 10 else (2 if n < 25 else 3))
	var boss_pool := [0, 1, 2, 3, 5, 6, 7, 8]
	var boss: int = boss_pool[(n - 1) % boss_pool.size()]
	var ch := {"id": 0, "name": "결계의 탑", "color": Color(0.7, 0.8, 1.0), "hp": 2.0 * pow(1.13, n - 1),
		"gold": mini(150 + n * 12, 900), "gems": mini(2 + n / 5, 9), "desc": "끝없이 이어지는 결계의 탑. 층마다 규칙이 바뀐다."}
	var d := {"name": "결계의 탑 %d층" % n, "rounds": 10, "mods": _random_mods(rng, mod_n), "boss": boss}
	if n % 10 == 0:
		d["boss"] = 4 if (n / 10) % 2 == 1 else 9
		d["name"] = "결계의 탑 %d층 · 수문장" % n
		d["rounds"] = 12
	return {"chapter": ch, "index": 0, "data": d, "id": "T%d" % n, "tower": n}


static func daily_id(date_str := "") -> String:
	var d := date_str if date_str != "" else Time.get_date_string_from_system()
	return "D" + d.replace("-", "")


static func daily_stage(id: String) -> Dictionary:
	## 오늘의 결계: 날짜로 정해지는 도전 (모두 같은 규칙)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(id.substr(1)) * 31 + 5
	var boss_pool := [0, 1, 2, 3, 5, 6, 7, 8]
	var mods := _random_mods(rng, 2 + rng.randi() % 2)
	var ch := {"id": 0, "name": "오늘의 결계", "color": Color(1, 0.8, 0.4), "hp": 6.0 + rng.randf() * 4.0,
		"gold": 350, "gems": 5, "desc": "매일 바뀌는 규칙의 도전. 하루 한 번 큰 보상!"}
	var d := {"name": "오늘의 결계", "rounds": 12, "mods": mods, "boss": boss_pool[rng.randi() % boss_pool.size()]}
	return {"chapter": ch, "index": 0, "data": d, "id": id, "daily": true}


static func stage_reward(id: String, old_stars: int, stars: int) -> Dictionary:
	## 스테이지 보상 코인. {first, new_stars, coins}
	var out := {"first": old_stars == 0 and stars > 0, "new_stars": maxi(0, stars - old_stars), "coins": 0}
	if id.begins_with("T"):
		var n := int(id.substr(1))
		if out["first"]:
			out["coins"] = 40 + n * 12 + (150 if n % 10 == 0 else 0)
		return out
	if id.begins_with("D"):
		out["coins"] = 300 if out["first"] else 0
		return out
	var ch := chapter_of(id)
	var mult := HARD_REWARD if id.begins_with("H") else 1.0
	if out["first"]:
		out["coins"] += int((40 + ch * 30) * mult)
	out["coins"] += int(out["new_stars"] * (15 + ch * 10) * mult)
	return out

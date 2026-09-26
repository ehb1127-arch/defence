class_name RunSave
## 장 이어하기 체크포인트: 스테이지를 이기면 "다음 스테이지 시작 상태"(배치·강화·재화·천장)를 저장해 두고,
## 지도에서 그 스테이지를 다시 골라도(또는 져서 다시 해도) 거기서 이어서 시작한다.
## 로컬 전용 (판 안의 상태라 서버 경제와 무관). user://runs.cfg

const PATH := "user://runs.cfg"

static var _cfg: ConfigFile = null


static func _load() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(PATH)
	return _cfg


static func has(stage_id: String) -> bool:
	return not get_state(stage_id).is_empty()


static func get_state(stage_id: String) -> Dictionary:
	var v: Variant = _load().get_value("run", stage_id, {})
	return v if v is Dictionary else {}


static func save_state(stage_id: String, state: Dictionary) -> void:
	if stage_id == "":
		return
	var c := _load()
	c.set_value("run", stage_id, state)
	c.save(PATH)


static func clear(stage_id: String) -> void:
	var c := _load()
	if c.has_section_key("run", stage_id):
		c.erase_section_key("run", stage_id)
		c.save(PATH)

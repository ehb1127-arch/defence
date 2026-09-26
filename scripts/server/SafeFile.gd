extends RefCounted
## 안전한 파일 저장 (서버 DB·결제 기록·기기 프로필 공통).
##
## 쓰기: 임시 파일(.tmp)에 다 쓴 뒤 이름 바꾸기로 교체 → 쓰는 도중 꺼져도 예전 파일이나 새 파일 중 하나는 온전하다.
## 백업: 시각이 붙은 복사본을 폴더에 두고 오래된 것부터 지운다.
## 읽기: 본 파일이 깨졌으면 가장 최근의 온전한 백업을 쓴다 (조용히 빈 DB 로 시작하지 않게).


static func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("user://") or path.begins_with("res://") else path


static func commit(tmp_path: String, path: String, bak_path := "") -> bool:
	## 다 쓴 임시 파일을 본 파일로 교체. bak_path 가 있으면 교체 전 파일을 거기로 옮겨 둔다
	if not FileAccess.file_exists(tmp_path):
		return false
	if bak_path != "" and FileAccess.file_exists(path):
		DirAccess.rename_absolute(_abs(path), _abs(bak_path))
	var err := DirAccess.rename_absolute(_abs(tmp_path), _abs(path))
	if err != OK:
		# 이름 바꾸기가 안 되는 파일 시스템: 복사로 대신
		err = DirAccess.copy_absolute(_abs(tmp_path), _abs(path))
		DirAccess.remove_absolute(_abs(tmp_path))
	return err == OK


static func write_text(path: String, text: String, bak_path := "") -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("저장 실패: %s (%d)" % [tmp, FileAccess.get_open_error()])
		return false
	f.store_string(text)
	f.flush()
	var ok := f.get_error() == OK
	f.close()
	if not ok:
		push_error("저장 실패: %s" % tmp)
		return false
	return commit(tmp, path, bak_path)


static func read_json(path: String) -> Variant:
	## 읽어서 JSON 해석. 없거나 깨졌으면 null
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges() == "":
		return null
	var j := JSON.new()
	if j.parse(text) != OK:
		return null
	return j.data


static func backup(path: String, dir: String, keep: int) -> String:
	## 시각이 붙은 복사본 만들기 (dir/<파일이름>-YYYYMMDD-HHMMSS.json). keep 개만 남긴다. 만든 경로 반환
	if not FileAccess.file_exists(path):
		return ""
	DirAccess.make_dir_recursive_absolute(_abs(dir))
	var base := path.get_file().get_basename()
	var stamp := Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "").replace("T", "-")
	var dst := dir.path_join("%s-%s.%s" % [base, stamp, path.get_extension()])
	if DirAccess.copy_absolute(_abs(path), _abs(dst)) != OK:
		push_error("백업 실패: %s" % dst)
		return ""
	var list := list_backups(path, dir)
	while list.size() > keep:
		DirAccess.remove_absolute(_abs(list.pop_front()))
	return dst


static func newest_backup_age(path: String, dir: String) -> float:
	## 가장 최근 백업이 만들어진 지 몇 초 지났나 (백업이 없으면 INF)
	var list := list_backups(path, dir)
	if list.is_empty():
		return INF
	# 파일 이름의 시각(UTC, YYYYMMDD-HHMMSS)으로 판단 (복사본의 수정 시각은 믿지 않는다)
	var stamp: String = str(list[list.size() - 1]).get_file().get_basename().right(15)
	if stamp.length() != 15 or stamp[8] != "-":
		return INF
	var iso := "%s-%s-%sT%s:%s:%s" % [stamp.substr(0, 4), stamp.substr(4, 2), stamp.substr(6, 2), stamp.substr(9, 2), stamp.substr(11, 2), stamp.substr(13, 2)]
	var t := Time.get_unix_time_from_datetime_string(iso)
	return maxf(0.0, Time.get_unix_time_from_system() - float(t))


static func list_backups(path: String, dir: String) -> Array:
	## 오래된 것부터 정렬한 백업 목록
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	var base := path.get_file().get_basename() + "-"
	for f in d.get_files():
		if f.begins_with(base) and f.get_extension() == path.get_extension():
			out.append(dir.path_join(f))
	out.sort()
	return out


static func load_json_with_backup(path: String, dir: String) -> Dictionary:
	## {data, source, corrupt}. 본 파일 → 임시 파일 → 최신 백업부터 순서대로 온전한 것을 쓴다.
	## corrupt = 본 파일이 있는데 깨져 있었음 (data 가 null 이면 복구할 수 없음)
	var out := {"data": null, "source": "", "corrupt": false}
	var d = read_json(path)
	if d is Dictionary:
		out["data"] = d
		out["source"] = path
		return out
	out["corrupt"] = FileAccess.file_exists(path)
	var candidates: Array = [path + ".tmp"]
	var list := list_backups(path, dir)
	list.reverse()
	candidates.append_array(list)
	for c in candidates:
		var b = read_json(c)
		if b is Dictionary:
			out["data"] = b
			out["source"] = c
			return out
	return out

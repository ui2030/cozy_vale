extends Node
# 입력 액션 등록 (DESIGN 11.4 — 액션 이름으로만 입력, 패드는 나중에 같은 액션에 매핑 추가)
# physical_keycode = 물리 키 위치 기준(비QWERTY 배열에서도 WASD 위치 유지).

func _ready() -> void:
	_add("move_up", [KEY_W, KEY_UP])
	_add("move_down", [KEY_S, KEY_DOWN])
	_add("move_left", [KEY_A, KEY_LEFT])
	_add("move_right", [KEY_D, KEY_RIGHT])
	_add("interact", [KEY_E, KEY_SPACE])  # 침대/상점/판매상자
	_add("use_tool", [KEY_F])             # 조준 타일에 상황별 동작(괭이·씨앗·물·수확)
	_add("cycle_seed", [KEY_Q])           # 선택 씨앗 순환

func _add(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)

extends CharacterBody3D
# 플레이어 이동 (DESIGN 11.4 — InputMap 액션 기반). 쿼터뷰 X-Z 평면 이동.

@export var speed := 5.0
@export var gravity := 24.0

@onready var _interact_area: Area3D = $InteractArea

func _physics_process(delta: float) -> void:
	# 중력 (바닥에 앉히기)
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# 화면 기준: move_up = 화면 위 = -Z
	var dir := Vector3(input.x, 0.0, input.y)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()

	# 이동 방향 바라보기 (상호작용 조준 기반)
	if dir.length() > 0.1:
		var target := global_position + dir
		look_at(Vector3(target.x, global_position.y, target.z), Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_try_interact()

func _try_interact() -> void:
	for a in _interact_area.get_overlapping_areas():
		if a.is_in_group("bed"):
			_sleep()
			return

# 취침: clock 갱신 → (day_changed 구독자 정산) → 저장 요청 (Codex 순서)
func _sleep() -> void:
	GameClock.sleep_to_morning()
	SaveManager.request_save("sleep")

func save_data() -> Dictionary:
	return {"pos": [global_position.x, global_position.y, global_position.z]}

func load_data(d: Dictionary) -> void:
	var p: Array = d.get("pos", [0.0, 2.0, 0.0])
	global_position = Vector3(p[0], p[1], p[2])

extends Camera3D
# 동물의 숲식 추종 카메라 — 캐릭터 뒤쪽에서 낮은 각도로 따라감 (고정 회전).

@export var offset := Vector3(0, 6.5, 9.5)  # 뒤(+Z)+위, 완만한 하향 (~35°)
@export var look_height := 1.2
@export var fov_deg := 48.0

var _target: Node3D

func _ready() -> void:
	_target = get_tree().get_first_node_in_group("player")
	fov = fov_deg

func _process(_delta: float) -> void:
	if _target == null:
		return
	global_position = _target.global_position + offset
	look_at(_target.global_position + Vector3.UP * look_height, Vector3.UP)

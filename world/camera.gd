extends Camera3D
# 쿼터뷰 추종 카메라 (DESIGN 3 — 고정 시점, 자유회전 없음).

@export var offset := Vector3(11, 13, 11)
@export var look_height := 1.0

var _target: Node3D

func _ready() -> void:
	_target = get_tree().get_first_node_in_group("player")

func _process(_delta: float) -> void:
	if _target == null:
		return
	global_position = _target.global_position + offset
	look_at(_target.global_position + Vector3.UP * look_height, Vector3.UP)

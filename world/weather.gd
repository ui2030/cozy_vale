extends Node3D
# 빗줄기 — 비 오는 날 플레이어 머리 위를 따라다니는 강수 파티클 하나.
# 날씨 판정은 GameData.is_rainy(abs_day) 단일 출처(세이브 없음, abs_day 결정적).
# 하늘 흐림은 day_night.gd가 같은 판정을 읽어 cloud_coverage로, 작물 자동 물주기는
# farm_system이 day_changed 순서 안에서 각자 처리한다 — 여기는 순수 시각 효과만.
#
# 실내 개념이 없는 게임이라 전역 강수로 충분하다. 소프트 수채 툰 그림체 기준:
# 스플래시·물웅덩이·굴절 없이 납작한 선만 떨어뜨린다.

const AREA := 14.0   # 플레이어 중심 강수 범위(한 변) — 고정 카메라 화각을 덮는 최소 크기
const TOP := 9.0     # 낙하 시작 높이

var _rain: GPUParticles3D
var _player: Node3D

func _ready() -> void:
	add_to_group("weather")
	_rain = _make_rain()
	add_child(_rain)

# 매 프레임 폴링: 세이브 로드·취침·자정 넘김이 전부 abs_day를 신호 없이 바꾼다
# (sfx.gd 앰비언스와 같은 이유 — 정수 비교 하나가 그 경계를 다 덮는다).
func _process(_dt: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	if _player != null:
		var p := _player.global_position
		global_position = Vector3(p.x, 0.0, p.z)  # 수평만 추종 (높이는 에미터가 고정)
	var want := GameData.is_rainy(GameClock.abs_day)
	if want != _rain.emitting:
		_rain.emitting = want

func _make_rain() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 1000
	p.lifetime = 0.9         # v0 8 + 중력 6 → 0.85초면 TOP에서 지면 도달 (땅 밑으로 새는 낭비 없음)
	p.preprocess = 0.9       # 켜자마자 화면이 차 있게 (위에서 스며드는 티 안 남)
	p.emitting = false
	p.local_coords = false   # 전역 좌표: 에미터가 플레이어를 따라가도 이미 떨어지는 빗방울은 끌려오지 않음
	p.position = Vector3(0, TOP, 0)
	# 추종 중 프러스텀 컬링으로 통째로 사라지지 않게 낙하 부피 전체를 수동 지정.
	# 에미터 로컬 기준이라 y는 아래로 파야 한다(위가 아니라) — TOP만큼 내려가 지면까지 + 여유.
	p.visibility_aabb = AABB(Vector3(-AREA, -(TOP + 1.0), -AREA), Vector3(AREA * 2.0, TOP + 2.0, AREA * 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(AREA * 0.5, 0.1, AREA * 0.5)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 0.0
	pm.initial_velocity_min = 7.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3(-1.5, -6.0, 0)  # 약한 바람 기울기
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.5)      # 가는 선 한 줄 = 빗줄기
	p.draw_pass_1 = quad
	# ponytail: 파티클은 네이티브 빌보드 StandardMaterial (툰셰이더는 인스턴스 변환 미지원 — festival_system과 동일)
	var mat := StandardMaterial3D.new()
	# 낮 하늘이 크림색이라 흰 빗줄기는 안 읽힌다 — 푸른기를 넣고 알파를 올려야 낮에도 비로 보인다.
	mat.albedo_color = Color(0.70, 0.81, 0.94, 0.70)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p.material_override = mat
	return p

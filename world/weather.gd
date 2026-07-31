extends Node3D
# 강수 — 비 오는 날 플레이어 머리 위를 따라다니는 파티클. 계절이 겨울이면 같은 강수일이 눈이 된다.
# 날씨 판정은 GameData.is_rainy(abs_day) 단일 출처(세이브 없음, abs_day 결정적).
# 하늘 흐림은 day_night.gd가 같은 판정을 읽어 cloud_coverage로, 작물 자동 물주기는
# farm_system이 day_changed 순서 안에서 각자 처리한다 — 여기는 순수 시각 효과만.
# (겨울은 작물이 없으므로 눈으로 바뀌어도 물주기 면제 로직은 그대로 통과한다.)
#
# 실내 개념이 없는 게임이라 전역 강수로 충분하다. 소프트 수채 툰 그림체 기준:
# 스플래시·물웅덩이·굴절 없이 비는 납작한 선, 눈은 둥근 점만 떨어뜨린다.

const Interior := preload("res://world/interior.gd")

const AREA := 14.0   # 플레이어 중심 강수 범위(한 변) — 고정 카메라 화각을 덮는 최소 크기
const TOP := 9.0     # 낙하 시작 높이
const WINTER := 3    # GameClock.SEASONS 인덱스

var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _player: Node3D

func _ready() -> void:
	add_to_group("weather")
	# ponytail: 두 에미터를 미리 만들고 emitting만 토글 — 계절이 바뀔 때마다 재생성하는 것보다 짧다.
	# (emitting=false인 GPUParticles3D는 시뮬레이션도 드로우도 돌지 않는다.)
	_rain = _make_precip(false)
	add_child(_rain)
	_snow = _make_precip(true)
	add_child(_snow)

# 매 프레임 폴링: 세이브 로드·취침·자정 넘김이 전부 abs_day를 신호 없이 바꾼다
# (sfx.gd 앰비언스와 같은 이유 — 정수 비교 하나가 그 경계를 다 덮는다).
func _process(_dt: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	if _player != null:
		var p := _player.global_position
		global_position = Vector3(p.x, 0.0, p.z)  # 수평만 추종 (높이는 에미터가 고정)
	# 실내(플레이어 집)에선 강수 정지 — 지붕 없는 오픈탑이라 비가 방 안으로 쏟아진다.
	var want := GameData.is_rainy(GameClock.abs_day) and not (_player != null and Interior.inside(_player.global_position))
	var snowing := want and GameClock.season() == WINTER
	var raining := want and not snowing
	if raining != _rain.emitting:
		_rain.emitting = raining
	if snowing != _snow.emitting:
		_snow.emitting = snowing

# 비/눈 공통 에미터. 낙하 부피·추종·컬링 규약은 같고 속도·모양·색만 갈린다.
func _make_precip(snow: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	# 눈은 천천히 오래 떨어진다 — 같은 화면 밀도를 훨씬 적은 수로 채운다(체공시간이 길어서).
	p.amount = 600 if snow else 1000
	# 비: v0 8 + 중력 6 → 0.85초면 TOP에서 지면 도달. 눈: v0 1.3 + 중력 0.5 → ~5초.
	p.lifetime = 5.0 if snow else 0.9
	# 켜자마자 화면이 차 있게 (위에서 스며드는 티 안 남).
	# ponytail: 눈은 체공 5초라 preprocess도 5초 — 강수 시작 한 프레임에 GPU가 5초치를 몰아 돈다.
	# 실측 스샷에선 문제 없었다. 겨울 첫 강수 전환에서 프레임 튐이 보이면 여기를 2~3초로 낮출 것.
	p.preprocess = p.lifetime
	p.emitting = false
	p.local_coords = false   # 전역 좌표: 에미터가 플레이어를 따라가도 이미 떨어지는 알갱이는 끌려오지 않음
	p.position = Vector3(0, TOP, 0)
	# 추종 중 프러스텀 컬링으로 통째로 사라지지 않게 낙하 부피 전체를 수동 지정.
	# 에미터 로컬 기준이라 y는 아래로 파야 한다(위가 아니라) — TOP만큼 내려가 지면까지 + 여유.
	p.visibility_aabb = AABB(Vector3(-AREA, -(TOP + 1.0), -AREA), Vector3(AREA * 2.0, TOP + 2.0, AREA * 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(AREA * 0.5, 0.1, AREA * 0.5)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 14.0 if snow else 0.0     # 눈은 수직으로 곧게 떨어지지 않는다(흩날림)
	pm.initial_velocity_min = 1.0 if snow else 7.0
	pm.initial_velocity_max = 1.6 if snow else 9.0
	# 바람 기울기 — 눈은 약하게(느린 낙하 중 옆으로 밀리는 게 보이도록 가로 성분 비율은 오히려 크게)
	pm.gravity = Vector3(-0.35, -0.5, 0.15) if snow else Vector3(-1.5, -6.0, 0)
	p.process_material = pm
	if snow:
		# 둥근 눈송이 — 빗줄기용 빌보드 쿼드는 각진 사각으로 읽힌다(카드 요구: 작고 둥글게).
		var sm := SphereMesh.new()
		sm.radius = 0.045
		sm.height = 0.09
		sm.radial_segments = 6
		sm.rings = 3
		p.draw_pass_1 = sm
	else:
		var quad := QuadMesh.new()
		quad.size = Vector2(0.025, 0.5)   # 가는 선 한 줄 = 빗줄기 (지면 스트리크는 눈엔 없음)
		p.draw_pass_1 = quad
	# ponytail: 파티클은 네이티브 빌보드 StandardMaterial (툰셰이더는 인스턴스 변환 미지원 — festival_system과 동일)
	var mat := StandardMaterial3D.new()
	# 비: 낮 하늘이 크림색이라 흰 빗줄기는 안 읽힌다 — 푸른기 + 알파를 올려야 낮에도 비로 보인다.
	# 눈: 순백은 밤 하늘에서 튄다 — 아주 옅은 청기를 남긴 근백색(지면 눈 톤과 같은 결).
	mat.albedo_color = Color(0.96, 0.97, 1.00, 0.92) if snow else Color(0.70, 0.81, 0.94, 0.70)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if not snow:  # 구는 어느 각도서도 둥글다 — 빌보드는 납작한 쿼드에만 필요
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p.material_override = mat
	return p

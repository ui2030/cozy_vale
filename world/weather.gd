extends Node3D
# 강수 — 비 오는 날 플레이어 머리 위를 따라다니는 파티클. 계절이 겨울이면 같은 강수일이 눈이 된다.
# 날씨 판정은 GameData.is_rainy(abs_day) 단일 출처(세이브 없음, abs_day 결정적).
# 하늘 흐림은 day_night.gd가 같은 판정을 읽어 cloud_coverage로, 작물 자동 물주기는
# farm_system이 day_changed 순서 안에서 각자 처리한다 — 여기는 순수 시각 효과만.
# (겨울은 작물이 없으므로 눈으로 바뀌어도 물주기 면제 로직은 그대로 통과한다.)
#
# 실내 개념이 없는 게임이라 전역 강수로 충분하다. 소프트 수채 툰 그림체 기준:
# 물웅덩이·굴절 없이 비는 가는 선 + 지면에 번지는 얇은 파문, 눈은 둥근 점만 떨어뜨린다.

const Interior := preload("res://world/interior.gd")

const AREA := 14.0   # 플레이어 중심 강수 범위(한 변) — 고정 카메라 화각을 덮는 최소 크기
const TOP := 9.0     # 낙하 시작 높이
const WINTER := 3    # GameClock.SEASONS 인덱스
# 파문 높이 = 초지 상면 0.10 + 0.03. 스플래시 셰이더가 지면과 **같은 월드 곡률**을 쓰므로
# 이 여유는 거리와 무관하게 일정하다(곡률을 빠뜨리면 먼 파문이 지면 위로 붕 뜬다).
const SPLASH_Y := 0.13

# 파문 셰이더 — 지면(ground.gdshader)·물(water.gdshader)과 같은 뷰공간 곡률을 그대로 복제한다.
# 링 모양은 텍스처(방사 그라디언트)가 내고, 여기선 색·알파와 곡률만 담당한다.
const SPLASH_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 tint : source_color = vec4(0.86, 0.92, 0.99, 1.0);
uniform sampler2D ring : source_color, filter_linear;
uniform float curve_strength = 0.006;  // toon.gdshader와 동일 월드 곡률

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.y -= curve_strength * v.z * v.z;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = tint.a * texture(ring, UV).a * COLOR.a;  // COLOR.a = 파티클 수명 페이드
}
"""

var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _splash: GPUParticles3D
var _player: Node3D

func _ready() -> void:
	add_to_group("weather")
	# ponytail: 에미터를 미리 만들고 emitting만 토글 — 계절이 바뀔 때마다 재생성하는 것보다 짧다.
	# (emitting=false인 GPUParticles3D는 시뮬레이션도 드로우도 돌지 않는다.)
	_rain = _make_precip(false)
	add_child(_rain)
	_snow = _make_precip(true)
	add_child(_snow)
	_splash = _make_splash()
	add_child(_splash)

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
	if raining != _splash.emitting:   # 파문은 비 전용 — 눈엔 없다
		_splash.emitting = raining
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
	var mat := StandardMaterial3D.new()
	if snow:
		# 둥근 눈송이 — 빗줄기용 빌보드 쿼드는 각진 사각으로 읽힌다(카드 요구: 작고 둥글게).
		var sm := SphereMesh.new()
		sm.radius = 0.045
		sm.height = 0.09
		sm.radial_segments = 6
		sm.rings = 3
		p.draw_pass_1 = sm
		# 눈: 순백은 밤 하늘에서 튄다 — 아주 옅은 청기를 남긴 근백색(지면 눈 톤과 같은 결).
		mat.albedo_color = Color(0.96, 0.97, 1.00, 0.92)
		# 구는 어느 각도서도 둥글다 — 빌보드 불필요(승인된 그림, 손대지 않음).
	else:
		# 빗줄기: 옛 값(0.025×0.5 · 단색 알파 0.70)은 화면에서 굵은 흰 막대로 읽혔다(유저 지적).
		# 가늘게(0.013) · 짧게(0.36) · 옅게 + 끝을 녹이는 세로 그라디언트로 "저화질 막대"를 없앤다.
		var quad := QuadMesh.new()
		quad.size = Vector2(0.014, 0.42)
		p.draw_pass_1 = quad
		# 낙하 벡터에 맞춰 눕는 빌보드. 재질 빌보드(BILLBOARD_PARTICLES)는 언제나 화면 수직이라
		# 바람 성분(gravity.x −1.5)이 그림에 안 나타났다 — 이제 줄기가 바람 방향으로 기운다.
		# (재질 빌보드와 동시 사용 금지 → mat.billboard_mode는 기본값 DISABLED 그대로 둔다.)
		p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
		pm.scale_min = 0.7    # 입자마다 길이 변주 — 같은 길이 1000개가 "저화질"의 절반이었다
		pm.scale_max = 1.3
		var vary := Gradient.new()   # 입자별 알파 변주(무작위 샘플) — 균일한 알파가 "인쇄된 무늬"로 읽혔다
		vary.set_color(0, Color(1, 1, 1, 0.55))
		vary.set_color(1, Color(1, 1, 1, 1.0))
		var vt := GradientTexture1D.new()
		vt.gradient = vary
		pm.color_initial_ramp = vt
		# 대비는 알파가 아니라 **색**으로 낸다. 알파를 올리면 밤(어두운 배경)만 다시 굵어지고
		# 낮(밝은 크림 하늘)은 그대로다 — 낮에 읽히려면 하늘보다 어두워야 한다(실측: 0.72/0.80/0.90은
		# 정오 하늘과 붙어 사라졌다). 0.62/0.71/0.85 = 낮엔 하늘보다 어둡고 밤엔 옛값보다 부드럽다.
		mat.albedo_color = Color(0.62, 0.71, 0.85, 0.55)
		mat.albedo_texture = _streak_tex()
		mat.vertex_color_use_as_albedo = true  # 없으면 color_initial_ramp가 통째로 무시된다
	# ponytail: 파티클은 네이티브 StandardMaterial (툰셰이더는 인스턴스 변환 미지원 — festival_system과 동일)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p.material_override = mat
	return p

# 지면 파문 — 비가 닿는 자리에 작은 링이 퍼지며 사라진다(코지 비의 관용구).
func _make_splash() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 220          # 비 1000줄기 대비 성긴 게 맞다 — 촘촘하면 지면이 얼룩덜룩해진다
	p.lifetime = 0.42
	p.emitting = false
	p.local_coords = false
	p.position = Vector3(0, SPLASH_Y, 0)
	p.visibility_aabb = AABB(Vector3(-AREA, -1.0, -AREA), Vector3(AREA * 2.0, 2.0, AREA * 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(AREA * 0.5, 0.01, AREA * 0.5)  # 빗줄기와 같은 발자국
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 0.0
	pm.initial_velocity_min = 0.0   # 제자리에서 퍼지기만 한다(튀어오르지 않음 = 툰 평면)
	pm.initial_velocity_max = 0.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.65             # 링 크기 변주
	pm.scale_max = 1.0
	var grow := Curve.new()         # 수명 동안 0.35 → 1.0으로 퍼짐
	grow.add_point(Vector2(0.0, 0.35))
	grow.add_point(Vector2(1.0, 1.0))
	var gt := CurveTexture.new()
	gt.curve = grow
	pm.scale_curve = gt
	# 알파: 짧게 나타났다 길게 녹는다(툭 튀어나오면 팝으로 읽힌다)
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.18, Color(1, 1, 1, 1))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	p.process_material = pm
	var plane := PlaneMesh.new()    # 기본 방향이 +Y 향 수평면 — 지면에 눕는다
	plane.size = Vector2(0.34, 0.34)
	p.draw_pass_1 = plane
	var sh := Shader.new()
	sh.code = SPLASH_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tint", Color(0.86, 0.92, 0.99, 0.55))
	mat.set_shader_parameter("ring", _ring_tex())
	p.material_override = mat
	return p

# 빗줄기 세로 알파 그라디언트 — 양 끝이 녹아 딱딱한 사각 끝(= "저화질")이 사라진다.
func _streak_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.28, Color(1, 1, 1, 1))
	g.add_point(0.72, Color(1, 1, 1, 1))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 4
	t.height = 64
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)   # 세로 방향(기본은 가로)
	return t

# 파문 링 — 중심에서 방사로 퍼지는 알파 고리 하나. 텍스처 파일 0.
func _ring_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.48, Color(1, 1, 1, 0))
	g.add_point(0.78, Color(1, 1, 1, 1))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 48
	t.height = 48
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t

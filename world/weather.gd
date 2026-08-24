extends Node3D
# 강수 — 비 오는 날 플레이어 머리 위를 따라다니는 파티클. 계절이 겨울이면 같은 강수일이 눈이 된다.
# 가을 낙엽도 같은 추종 규약을 쓰므로 여기 산다(강수 판정과는 무관 — _make_leaves 주석).
# 날씨 판정은 GameData.is_rainy(abs_day) 단일 출처(세이브 없음, abs_day 결정적).
# 하늘 흐림은 day_night.gd가 같은 판정을 읽어 cloud_coverage로, 작물 자동 물주기는
# farm_system이 day_changed 순서 안에서 각자 처리한다 — 여기는 순수 시각 효과만.
# (겨울은 작물이 없으므로 눈으로 바뀌어도 물주기 면제 로직은 그대로 통과한다.)
#
# 실내 개념이 없는 게임이라 전역 강수로 충분하다. 소프트 수채 툰 그림체 기준:
# 물웅덩이·굴절 없이 비는 가는 선 + 지면에 번지는 얇은 파문, 눈은 둥근 점만 떨어뜨린다.

const Interior := preload("res://world/interior.gd")
const WorldScript := preload("res://world/world.gd")  # 강 폴리라인·물 상면 단일 출처
const Beach := preload("res://world/beach.gd")        # 바다 판 단일 출처

const AREA := 14.0   # 플레이어 중심 강수 범위(한 변) — 고정 카메라 화각을 덮는 최소 크기
const TOP := 9.0     # 낙하 시작 높이
const AUTUMN := 2    # GameClock.SEASONS 인덱스
const WINTER := 3
# 빗줄기 원근용 낙하 부피(비 전용). AREA 상자 안에선 화면에 잡히는 비가 전부 카메라 8~17m라
# 굵기·화면속도·밀도가 다 같아 "커튼"으로 읽혔다 — 실측으로 12m 하드컷을 걸어도 그림이 안 변한다,
# 즉 애초에 **먼 비가 없었다**. 알파 커브만으로는 못 만드는 문제라 부피를 깊고 넓게 잡는다.
# 상자를 -Z로 미는 건 카메라가 고정 방위(플레이어 +Z 뒤에서 -Z를 봄)라서 — 이 전제는
# sky.gdshader 별자리 배치가 이미 쓰고 있다.
const RAIN_W := 30.0   # 좌우 폭 (원경 30m에서 화각을 덮는 최소치)
const RAIN_D := 30.0   # 앞뒤 깊이 → 카메라 거리 ~2.5m(프레임 하단) ~ ~33m(지평선)
const RAIN_Z := -8.0   # 상자 중심 z(플레이어 기준): 근거리 +7, 원경 -23
# 파문 높이 = 초지 상면 0.10 + 0.03. 스플래시 셰이더가 지면과 **같은 월드 곡률**을 쓰므로
# 이 여유는 거리와 무관하게 일정하다(곡률을 빠뜨리면 먼 파문이 지면 위로 붕 뜬다).
const SPLASH_Y := 0.13
const WATER_CAPS := 10  # 셰이더 물 영역 배열 크기 = 강 6세그먼트 + 연못 + 바다 + 여유

# 파문 셰이더 — 지면(ground.gdshader)·물(water.gdshader)과 같은 뷰공간 곡률을 그대로 복제한다.
# 링 모양은 텍스처(방사 그라디언트)가 내고, 여기선 색·알파와 곡률만 담당한다.
#
# 물 위 파문: GPUParticles는 입자 배치가 GPU 몫이라 CPU에서 개별 y를 못 준다 → 여기서
# 월드 xz가 물이면 파문을 그 수면 위로 올린다. 안 하면 지면 높이(0.13)가 물 상면(강 0.23·
# 연못 0.18·바다 0.18)보다 낮아 불투명 툰 물에 통째로 가린다 = 비 오는 날 수면만 잠잠함.
const SPLASH_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform vec4 tint : source_color = vec4(0.86, 0.92, 0.99, 1.0);
uniform sampler2D ring : source_color, filter_linear;
uniform float curve_strength = 0.006;  // toon.gdshader와 동일 월드 곡률
// 물 영역 = 캡슐(선분 ab + 반경) 목록. 강 세그먼트·연못(a==b인 원)·바다를 한 형태로 통일한다.
uniform vec4 water_ab[10];   // (ax, az, bx, bz) 월드 xz
uniform vec2 water_ry[10];   // (반경, 수면 상면 y)
uniform int water_n = 0;
uniform float water_lift = 0.03;  // 수면 위 여유(지면 파문이 초지 위에 뜨는 폭과 같다)

// 입자별 난수(0~1). 인스턴스 원점에서 뽑으므로 한 입자 안에선 상수다(VERTEX에서 뽑으면
// 꼭짓점마다 달라져 면 위에서 뭉개진다). 고리마다 다른 위상을 주는 데만 쓴다.
varying float seed;
// 마른 지면에선 옅게, 수면에선 그대로. 잔디 위 파문은 물이 고인 자국이 아니라 튄 물방울이라
// 같은 밝기로 찍으면 "흰 동그라미 도배"가 된다(실측 audit2/rain_pavilion_h18).
varying float dim;

// xz가 물이면 그 수면 상면 y, 아니면 -1000.0
float water_top(vec2 p) {
	for (int i = 0; i < water_n; i++) {
		vec2 a = water_ab[i].xy;
		vec2 ab = water_ab[i].zw - a;
		// 연못은 a == b(길이 0) — 나눗셈 보호가 없으면 NaN이 되어 판정이 통째로 샌다.
		float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
		if (distance(p, a + ab * t) < water_ry[i].x) {
			return water_ry[i].y;
		}
	}
	return -1000.0;
}

void vertex() {
	vec4 w = MODEL_MATRIX * vec4(VERTEX, 1.0);   // 입자 인스턴스 변환 포함 = 월드 좌표
	float wy = water_top(w.xz);
	dim = 0.45;
	if (wy > -999.0) {
		w.y = wy + water_lift;
		// 1.8 = 새로 곱해진 산포(입자별 밝기 평균 0.68 × 고리 끊김 평균 0.75)의 역수.
		// 수면 파문의 화면 밝기를 옛 값 그대로 돌려놓는다 — 강·연못·바다 회귀 방지.
		dim = 1.8;
	}
	seed = fract(sin(dot(MODEL_MATRIX[3].xz, vec2(12.9898, 78.233))) * 43758.5453);
	vec4 v = VIEW_MATRIX * w;
	v.y -= curve_strength * v.z * v.z;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	// 완전한 원 대신 세 갈래로 성긴 고리. 위상이 입자마다 달라 같은 도장을 찍은 무늬가 안 된다.
	vec2 d = UV - vec2(0.5);
	float wob = 0.5 + 0.5 * sin(atan(d.y, d.x) * 3.0 + seed * 6.2831);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * texture(ring, UV).a * COLOR.a * dim * mix(0.5, 1.0, wob);  // COLOR.a = 수명 페이드 × 입자별 밝기
}
"""

var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _leaves: GPUParticles3D
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
	_leaves = _make_leaves()
	add_child(_leaves)
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
	var outside := not (_player != null and Interior.inside(_player.global_position))
	var want := GameData.is_rainy(GameClock.abs_day) and outside
	var snowing := want and GameClock.season() == WINTER
	var raining := want and not snowing
	# 낙엽은 강수가 아니다 — 가을이면 맑은 날에도 흩날린다(is_rainy와 무관, 실내 규약만 공유).
	var falling := GameClock.season() == AUTUMN and outside
	if raining != _rain.emitting:
		_rain.emitting = raining
	if raining != _splash.emitting:   # 파문은 비 전용 — 눈엔 없다
		_splash.emitting = raining
	if snowing != _snow.emitting:
		_snow.emitting = snowing
	if falling != _leaves.emitting:
		_leaves.emitting = falling

# 비/눈 공통 에미터. 낙하 부피·추종·컬링 규약은 같고 속도·모양·색만 갈린다.
func _make_precip(snow: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	# 눈은 AREA 상자로 충분하다(느려서 알갱이를 눈으로 따라가고, 원경 눈은 점이라 안 보인다).
	# 비만 RAIN_* 깊은 상자를 쓴다 — 부피가 4.6배라 같은 근거리 밀도를 유지하려면 수도 올려야 한다.
	var bw := AREA if snow else RAIN_W
	var bd := AREA if snow else RAIN_D
	# 눈은 천천히 오래 떨어진다 — 같은 화면 밀도를 훨씬 적은 수로 채운다(체공시간이 길어서).
	# 눈 600은 "같은 크기 흰 원"이라 산포를 준 뒤 평균 크기가 줄어 800으로 채운다.
	p.amount = 800 if snow else 3200
	# 비: v0 8 + 중력 6 → 0.85초면 TOP에서 지면 도달. 눈: v0 1.3 + 중력 0.5 → ~5초.
	p.lifetime = 5.0 if snow else 0.9
	# 켜자마자 화면이 차 있게 (위에서 스며드는 티 안 남).
	# ponytail: 눈은 체공 5초라 preprocess도 5초 — 강수 시작 한 프레임에 GPU가 5초치를 몰아 돈다.
	# 실측 스샷에선 문제 없었다. 겨울 첫 강수 전환에서 프레임 튐이 보이면 여기를 2~3초로 낮출 것.
	p.preprocess = p.lifetime
	p.emitting = false
	p.local_coords = false   # 전역 좌표: 에미터가 플레이어를 따라가도 이미 떨어지는 알갱이는 끌려오지 않음
	p.position = Vector3(0, TOP, 0.0 if snow else RAIN_Z)
	# 추종 중 프러스텀 컬링으로 통째로 사라지지 않게 낙하 부피 전체를 수동 지정.
	# 에미터 로컬 기준이라 y는 아래로 파야 한다(위가 아니라) — TOP만큼 내려가 지면까지 + 여유.
	p.visibility_aabb = AABB(Vector3(-bw, -(TOP + 1.0), -bd), Vector3(bw * 2.0, TOP + 2.0, bd * 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(bw * 0.5, 0.1, bd * 0.5)
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
		# 눈송이가 전부 같은 크기 = 흰 점 도배(실측 audit2/snow_houses_h12). 굵은 함박눈과
		# 가루눈이 섞여야 눈으로 읽힌다 — 낙하 속도 산포(체공시간)까지 같이 흐트러뜨린다.
		pm.scale_min = 0.45
		pm.scale_max = 1.35
		pm.lifetime_randomness = 0.3
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
		# 원근 나머지 절반: 굵기·길이·화면속도는 투영이 낸다(RAIN_* 상자가 먼 비를 만들어 준 뒤부터).
		# 대기 감쇄만 남으므로 네이티브 거리 페이드로 알파를 카메라 거리에 건다.
		# min>max = 멀어질수록 옅어짐(반전 동작). 42/6은 프레임 하단 ~8m에서 알파 1.0,
		# 지평선 ~33m에서 ~0.16 — 대역 안에서 0이 되지 않아 원경 비가 뚝 끊기지 않는다.
		mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		mat.distance_fade_min_distance = 42.0
		mat.distance_fade_max_distance = 6.0
	# ponytail: 파티클은 네이티브 StandardMaterial (툰셰이더는 인스턴스 변환 미지원 — festival_system과 동일)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p.material_override = mat
	return p

# 가을 낙엽 — 눈과 같은 낙하 규약(느리게 오래, 플레이어 추종)이지만 **강수가 아니다**.
# _make_precip(snow: bool)에 셋째 상태로 끼우지 않는다: 불리언 인자가 3분기를 받는 순간 그 함수의
# 모든 삼항이 무너지고(속도·부피·수·모양·색이 전부 snow 하나로 갈려 있다) 호출부까지 번진다.
# 구조만 베끼고 별개 함수로 둔다.
func _make_leaves() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	# 강수가 아니라 **악센트**다 — 눈(800)만큼 깔면 가을이 낙엽 폭설로 읽힌다.
	p.amount = 70
	p.lifetime = 7.0   # v0 0.4~0.9 + 중력 0.35 → TOP 9에서 지면까지 ~6.5초(흩날리며 천천히)
	p.preprocess = p.lifetime  # 켜자마자 화면이 차 있게(눈과 같은 이유)
	p.emitting = false
	p.local_coords = false     # 전역 좌표: 에미터가 따라가도 떨어지던 잎은 끌려오지 않음
	p.position = Vector3(0, TOP, 0)
	p.visibility_aabb = AABB(Vector3(-AREA, -(TOP + 1.0), -AREA), Vector3(AREA * 2.0, TOP + 2.0, AREA * 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(AREA * 0.5, 0.1, AREA * 0.5)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 30.0            # 잎은 곧게 안 떨어진다(눈 14보다 크게)
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 0.9
	# 가로 성분이 낙하보다 커야 "떨어진다"가 아니라 "흩날린다"로 읽힌다(눈은 반대로 세로가 크다).
	pm.gravity = Vector3(-0.55, -0.35, 0.20)
	# 회전이 눈송이와 갈리는 지점이다 — 안 돌면 같은 색 종잇조각이 수직으로 내려올 뿐이다.
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -110.0
	pm.angular_velocity_max = 110.0
	pm.scale_min = 0.6
	pm.scale_max = 1.15
	pm.lifetime_randomness = 0.35
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.13, 0.09)  # 잎 한 장. 더 키우면 근경에서 판때기로 읽힌다(빗줄기 전례)
	p.draw_pass_1 = quad
	var mat := StandardMaterial3D.new()
	# unshaded + 블룸이라 이 값보다 화면이 한참 밝게 뜬다 → albedo 상수가 아니라 **화면 목표값**에서
	# 역산한다(빗줄기 색과 같은 규약). 1차 실측(0.82,0.58,0.34)은 화면에서 크림 티끌로 날아가
	# 하늘과 붙었다 — 수관 단풍(정오 화면 (211,154,89))과 같은 대역으로 내려 잎이 나무에서
	# 떨어졌다는 게 색으로 읽히게 한다.
	mat.albedo_color = Color(0.70, 0.40, 0.19, 0.95)
	mat.albedo_texture = _leaf_tex()  # 쿼드 그대로면 각진 색종이가 된다(1차 실측)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # 돌면서 뒷면이 온다 — 안 끄면 잎이 깜빡인다
	# ponytail: 파티클은 네이티브 StandardMaterial (툰셰이더는 인스턴스 변환 미지원 — _make_precip과 동일)
	p.material_override = mat
	return p

# 지면 파문 — 비가 닿는 자리에 작은 링이 퍼지며 사라진다(코지 비의 관용구).
func _make_splash() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	# 220은 잔디를 흰 고리로 도배했다(실측). 밀도를 조금 내리고 남은 고리에 산포를 준다 —
	# 밀도로만 해결하면 수면 파문(같은 에미터)까지 성겨진다. 지면 쪽은 알파(dim)로 죽인다.
	p.amount = 200
	p.lifetime = 0.42
	p.emitting = false
	p.local_coords = false
	p.position = Vector3(0, SPLASH_Y, 0)
	p.visibility_aabb = AABB(Vector3(-AREA, -1.0, -AREA), Vector3(AREA * 2.0, 2.0, AREA * 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# 파문은 근거리(AREA)만 — 빗줄기 상자(RAIN_D 30m)를 다 덮으면 30m 밖 링이 서브픽셀이라
	# 입자만 낭비된다. 원경 파문 부재는 원근 자체가 가려 준다.
	pm.emission_box_extents = Vector3(AREA * 0.5, 0.01, AREA * 0.5)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 0.0
	pm.initial_velocity_min = 0.0   # 제자리에서 퍼지기만 한다(튀어오르지 않음 = 툰 평면)
	pm.initial_velocity_max = 0.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.35             # 링 크기 변주 — 0.65~1.0은 눈에 다 같은 크기로 읽혔다
	pm.scale_max = 1.2
	pm.lifetime_randomness = 0.35   # 수명이 같으면 온 화면이 같은 박자로 깜빡인다
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
	# 입자별 밝기 변주(무작위 샘플) — 빗줄기와 같은 처방. 균일한 알파가 "인쇄된 무늬"의 절반이었다.
	var vary := Gradient.new()
	vary.set_color(0, Color(1, 1, 1, 0.35))
	vary.set_color(1, Color(1, 1, 1, 1.0))
	var vt := GradientTexture1D.new()
	vt.gradient = vary
	pm.color_initial_ramp = vt
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
	_set_water(mat)
	p.material_override = mat
	return p

# 물 영역을 캡슐 목록으로 셰이더에 넘긴다. 좌표는 전부 기존 단일 출처에서 파생한다 —
# 강은 world.gd 폴리라인, 연못은 world.tscn 노드의 실제 AABB, 바다는 beach.gd 상수.
func _set_water(mat: ShaderMaterial) -> void:
	var ab := PackedVector4Array()
	var ry := PackedVector2Array()
	var pts: Array = WorldScript.RIVER_PTS
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		ab.append(Vector4(a.x, a.y, b.x, b.y))
		ry.append(Vector2(WorldScript.RIVER_W * 0.5, WorldScript.WATER_TOP))
	# 연못: 그룹 "water" 노드의 수면 메시(원기둥) AABB = 중심·반경·상면. 좌표 복제 0.
	# (해변 낚시 트리거도 같은 그룹이지만 메시 자식이 없어 자연히 걸러진다.)
	for n in get_tree().get_nodes_in_group("water"):
		for c in n.get_children():
			var mi := c as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var box: AABB = mi.global_transform * mi.mesh.get_aabb()
			var ctr := box.get_center()
			ab.append(Vector4(ctr.x, ctr.z, ctr.x, ctr.z))
			ry.append(Vector2(box.size.x * 0.5, box.end.y))
	# 바다: 판 남단이 아니라 **젖은 모래 띠** 안쪽까지 덮는다(띠가 수면보다 0.02 높고 물가선을
	# 침식으로 흔들기 때문 — 띠 남단까지 늘리면 파인 자리에서 파문이 마른 모래 위에 뜬다).
	var sea := Beach.ORIGIN + Beach.SEA_REL
	var z0 := sea.z - Beach.SEA_D * 0.5
	var z1 := Beach.ORIGIN.z + Beach.WET_Z + Beach.WET_D * 0.5 - Beach.WET_ERODE
	var r := (z1 - z0) * 0.5
	var cz := (z0 + z1) * 0.5
	ab.append(Vector4(sea.x - Beach.SEA_W * 0.5 + r, cz, sea.x + Beach.SEA_W * 0.5 - r, cz))
	ry.append(Vector2(r, Beach.WATER_Y + 0.02))
	if ab.size() > WATER_CAPS:
		push_warning("파문 물 영역 %d개 > 셰이더 배열 %d — 초과분 무시" % [ab.size(), WATER_CAPS])
	mat.set_shader_parameter("water_n", mini(ab.size(), WATER_CAPS))
	ab.resize(WATER_CAPS)   # 배열 uniform은 선언 크기로 채워 넘긴다
	ry.resize(WATER_CAPS)
	mat.set_shader_parameter("water_ab", ab)
	mat.set_shader_parameter("water_ry", ry)

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

# 잎 한 장 알파 — 방사 그라디언트 하나로 쿼드의 모서리를 지운다(텍스처 파일 0, 파문 링과 같은 수법).
# 쿼드를 그대로 쓰면 화면에서 **각진 색종이**로 읽힌다 — 빗줄기가 "굵은 흰 막대"였던 것과 같은 실패다.
# 쿼드가 정사각이 아니라(0.13×0.09) 원이 눌려 타원 = 잎 한 장으로 읽힌다.
func _leaf_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.60, Color(1, 1, 1, 1))  # 가운데는 꽉 차고 가장자리만 녹인다(솜뭉치 방지)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 32
	t.height = 32
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
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

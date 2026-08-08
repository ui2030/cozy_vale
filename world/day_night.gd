extends Node3D
# 낮밤 조명 사이클 — GameClock 시:분을 연속값(game_min/60.0)으로 읽어 태양·환경광·하늘을 매 프레임 보간.
# 낮(9~16시)=승인된 룩 그대로: 두 키프레임을 승인값으로 동일하게 둬 구간 상수(픽셀 아닌 조명 불변).
# 세이브 상태 없음(조명=시각 파생). 일시정지는 GameClock이 멈추므로 자동 대응.

# 키프레임(시각 오름차순): 태양 각도·색·에너지 + 환경광 색·에너지. 하늘 그라데이션/별은 sky.gdshader가 hour로 자체 처리.
const KEYS := [
	# 심야/밤 — 달빛 시프트 + 감광하되 실루엣 판독 가능(암흑 금지, 밤낚시 가능한 밝기).
	# 청색 편향은 **초지 albedo의 G/B 비(0.72/0.576 = 1.25)보다 약해야** 한다. 옛 값은 amb B/G가
	# 1.375라 초지가 밤에 청록으로 뒤집혔다(실측 21시: G 0.196 < B 0.220). 지금은 B/G 1.12·1.21로
	# 낮춰 초록이 유지된다. Rec.709 휘도는 옛 값과 동일(0.402/0.625) — 밤 밝기는 회귀 없음.
	{"h": 0.0,  "sun_rot": Vector3(-58, -125, 0), "sun_col": Color(0.56, 0.63, 0.76), "sun_e": 0.18, "amb_col": Color(0.36, 0.41, 0.46), "amb_e": 0.40},
	{"h": 5.0,  "sun_rot": Vector3(-58, -125, 0), "sun_col": Color(0.56, 0.63, 0.76), "sun_e": 0.18, "amb_col": Color(0.36, 0.41, 0.46), "amb_e": 0.40},
	# 아침(6~9) = 낮은 태양. 옛 값은 6.5시 고도 20°·8시 40°로 정오(52°)와 그림자 길이가 사실상
	# 같았고(cot 40°=1.19 vs cot 52°=0.78), 8시 환경광(0.78,0.74,0.76 e0.53)이 낮(0.78,0.76,0.82
	# e0.55)과 구별이 안 돼 "아침이 없었다". 세 축을 다 벌린다:
	#   · 고도 9°/19° — 그림자가 정오의 8배/4배 길이
	#   · 방위 -90°→-125° — 아침 그림자가 낮과 **다른 방향**으로 눕는다(태양이 하늘을 가로지른다)
	#   · 환경광을 낮보다 어둡고 살짝 청색으로 — 직광은 따뜻하고 그늘은 서늘한 아침 대비
	{"h": 6.5,  "sun_rot": Vector3(-9, -90, 0),   "sun_col": Color(0.90, 0.82, 0.80), "sun_e": 0.42, "amb_col": Color(0.56, 0.58, 0.66), "amb_e": 0.47},
	{"h": 8.0,  "sun_rot": Vector3(-19, -105, 0), "sun_col": Color(1.00, 0.90, 0.73), "sun_e": 0.78, "amb_col": Color(0.66, 0.67, 0.74), "amb_e": 0.50},
	# 낮 = 승인값(불변). 9시에 색·에너지는 이미 승인값이지만 태양은 아직 오르는 중이라
	# 11시에야 정오 각도에 닿는다 → 10시(-40°)가 정오(-52°)와 그림자로 구별된다. 11~16은 두 점 동일 → 상수.
	{"h": 9.0,  "sun_rot": Vector3(-28, -115, 0), "sun_col": Color(1, 1, 1),          "sun_e": 1.00, "amb_col": Color(0.78, 0.76, 0.82), "amb_e": 0.55},
	{"h": 11.0, "sun_rot": Vector3(-52, -125, 0), "sun_col": Color(1, 1, 1),          "sun_e": 1.00, "amb_col": Color(0.78, 0.76, 0.82), "amb_e": 0.55},
	{"h": 16.0, "sun_rot": Vector3(-52, -125, 0), "sun_col": Color(1, 1, 1),          "sun_e": 1.00, "amb_col": Color(0.78, 0.76, 0.82), "amb_e": 0.55},
	# 노을 골든아워(가장 예쁠 시간대) — 따뜻한 주황·보라, 태양 지평선 근처 낮게.
	{"h": 18.0, "sun_rot": Vector3(-14, -125, 0), "sun_col": Color(1.00, 0.72, 0.42), "sun_e": 0.95, "amb_col": Color(0.85, 0.62, 0.52), "amb_e": 0.52},
	# 황혼 보라 → 밤으로 감광
	{"h": 19.5, "sun_rot": Vector3(-4, -125, 0),  "sun_col": Color(0.85, 0.52, 0.50), "sun_e": 0.42, "amb_col": Color(0.52, 0.44, 0.62), "amb_e": 0.45},
	{"h": 21.0, "sun_rot": Vector3(-58, -125, 0), "sun_col": Color(0.56, 0.63, 0.76), "sun_e": 0.18, "amb_col": Color(0.36, 0.41, 0.46), "amb_e": 0.40},
	{"h": 24.0, "sun_rot": Vector3(-58, -125, 0), "sun_col": Color(0.56, 0.63, 0.76), "sun_e": 0.18, "amb_col": Color(0.36, 0.41, 0.46), "amb_e": 0.40},
]

# 날씨 → 하늘 흐림 + 조도 저하. 키프레임(위 KEYS)과 sample()은 그대로 두고 **적용 시점에만** 곱한다
# — sample()은 test_core가 핀한 순수 함수이고 승인된 낮/노을/밤 값 자체는 불변이어야 하기 때문.
const CLOUD_CLEAR := 0.32   # sky.gdshader 기본값
const CLOUD_RAIN := 0.85
const CLOUD_RATE := 0.6     # 초당 전이량 (자정 날짜 전환 시 구름이 툭 튀지 않게)
const RAIN_SUN := 0.55      # 흐린 날 태양 에너지 배율 (구름이 직사광을 먹는다)
# 흐린 날 그림자: 번지고 + 옅어진다. blur만으론 경계폭이 24px→26px밖에 안 벌어져(실측) 체감이 없다 —
# 직사광이 구름에 산란되면 그림자가 흐려지는 게 아니라 사실상 사라진다 → opacity가 실효 레버.
const RAIN_BLUR := 4.5      # shadow_blur (기본 1.0)
const RAIN_SHADOW := 0.45   # shadow_opacity (기본 1.0)
const RAIN_AMB := 0.7       # 환경광을 청회색 쪽으로 끄는 비율 → 지면 채도가 같이 내려간다
                            # (초지·흙길·판석 공통 경로 = 조명. 지면 셰이더는 손 안 댐)
const RAIN_AMB_DIM := 0.88  # 그때의 감광폭. 고정 색으로 lerp하면 밤 환경광이 오히려 밝아진다 —
                            # 키프레임 luminance 기준 **상대값**이라 낮·노을·밤 모두 어두워지는 방향.

var _sun: DirectionalLight3D
var _env: Environment
var _sky_mat: ShaderMaterial
var _cov := -1.0  # 음수 = 미초기화(첫 프레임은 스냅)

func _process(dt: float) -> void:
	if _sun == null:
		_cache()  # world.gd _ready(_add_env)가 자식(this)보다 늦게 돌아 지연 캐시
		if _sun == null:
			return
	var h := GameClock.game_min / 60.0  # 연속값(분 단위 부드럽게, 스냅 없음)
	RenderingServer.global_shader_parameter_set("time_of_day", h)  # 물 셰이더(연못·강·바다 공용 머티리얼 다수)
	var p := sample(h)
	# 흐림 전이 0~1. 구름량과 **같은 램프**를 공유해 하늘·태양·환경광이 한 몸으로 움직인다
	# (하늘만 흐려지고 조명은 맑은 날이던 게 "비 오는 날이 더 화창"의 원인이었다).
	var cov_t := CLOUD_RAIN if GameData.is_rainy(GameClock.abs_day) else CLOUD_CLEAR
	_cov = cov_t if _cov < 0.0 else move_toward(_cov, cov_t, dt * CLOUD_RATE)
	var oc := (_cov - CLOUD_CLEAR) / (CLOUD_RAIN - CLOUD_CLEAR)
	_sun.rotation_degrees = p["sun_rot"]
	_sun.light_color = p["sun_col"]
	_sun.light_energy = p["sun_e"] * lerpf(1.0, RAIN_SUN, oc)
	_sun.shadow_blur = lerpf(1.0, RAIN_BLUR, oc)
	_sun.shadow_opacity = lerpf(1.0, RAIN_SHADOW, oc)
	if _env != null:
		var amb: Color = p["amb_col"]
		var g: float = amb.get_luminance() * RAIN_AMB_DIM
		_env.ambient_light_color = amb.lerp(Color(g * 0.94, g, g * 1.12), oc * RAIN_AMB)  # 청회색 편향
		_env.ambient_light_energy = p["amb_e"]
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("time_of_day", h)
		_sky_mat.set_shader_parameter("cloud_coverage", _cov)
		_sky_mat.set_shader_parameter("overcast", oc)

func _cache() -> void:
	_sun = get_node_or_null("../Sun") as DirectionalLight3D
	_env = get_viewport().get_world_3d().environment  # 런타임 생성 WorldEnvironment의 활성 env (이름 가정 없음)
	if _env != null and _env.sky != null:
		_sky_mat = _env.sky.sky_material as ShaderMaterial

# 야간 등화 계수 0(대낮)~1(밤). 실내등·가로등·창불빛이 전부 여기서 파생한다 —
# 시각 분기를 각자 발명하면 해질녘에 실내는 켜졌는데 마을은 안 켜지는 식으로 어긋난다.
static func night_factor(h: float) -> float:
	return 1.0 - smoothstep(0.25, 0.9, float(sample(h)["sun_e"]))

# 순수 함수: 시각(0~24) → 조명 파라미터. 구간 lerp. static이라 테스트에서 노드 없이 호출.
static func sample(h: float) -> Dictionary:
	for i in KEYS.size() - 1:
		var a: Dictionary = KEYS[i]
		var b: Dictionary = KEYS[i + 1]
		if h >= a["h"] and h <= b["h"]:
			var span: float = b["h"] - a["h"]
			var t: float = 0.0 if span == 0.0 else (h - a["h"]) / span
			return {
				"sun_rot": (a["sun_rot"] as Vector3).lerp(b["sun_rot"], t),
				"sun_col": (a["sun_col"] as Color).lerp(b["sun_col"], t),
				"sun_e": lerpf(a["sun_e"], b["sun_e"], t),
				"amb_col": (a["amb_col"] as Color).lerp(b["amb_col"], t),
				"amb_e": lerpf(a["amb_e"], b["amb_e"], t),
			}
	var last: Dictionary = KEYS[KEYS.size() - 1]  # h가 [0,24] 밖(방어)
	return {"sun_rot": last["sun_rot"], "sun_col": last["sun_col"], "sun_e": last["sun_e"], "amb_col": last["amb_col"], "amb_e": last["amb_e"]}

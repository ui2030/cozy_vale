extends Node3D
# 낮밤 조명 사이클 — GameClock 시:분을 연속값(game_min/60.0)으로 읽어 태양·환경광·하늘을 매 프레임 보간.
# 낮(9~16시)=승인된 룩 그대로: 두 키프레임을 승인값으로 동일하게 둬 구간 상수(픽셀 아닌 조명 불변).
# 세이브 상태 없음(조명=시각 파생). 일시정지는 GameClock이 멈추므로 자동 대응.

# 키프레임(시각 오름차순): 태양 각도·색·에너지 + 환경광 색·에너지. 하늘 그라데이션/별은 sky.gdshader가 hour로 자체 처리.
const KEYS := [
	# 심야/밤 — 청보라 시프트 + 감광하되 실루엣 판독 가능(암흑 금지, 밤낚시 가능한 밝기).
	{"h": 0.0,  "sun_rot": Vector3(-58, -125, 0), "sun_col": Color(0.55, 0.62, 0.90), "sun_e": 0.18, "amb_col": Color(0.36, 0.40, 0.55), "amb_e": 0.40},
	{"h": 5.0,  "sun_rot": Vector3(-58, -125, 0), "sun_col": Color(0.55, 0.62, 0.90), "sun_e": 0.18, "amb_col": Color(0.36, 0.40, 0.55), "amb_e": 0.40},
	# 새벽 청회색 → 따뜻
	{"h": 6.5,  "sun_rot": Vector3(-20, -125, 0), "sun_col": Color(0.72, 0.76, 0.92), "sun_e": 0.45, "amb_col": Color(0.55, 0.58, 0.70), "amb_e": 0.48},
	{"h": 8.0,  "sun_rot": Vector3(-40, -125, 0), "sun_col": Color(1.00, 0.88, 0.74), "sun_e": 0.85, "amb_col": Color(0.78, 0.74, 0.76), "amb_e": 0.53},
	# 낮 = 승인값(불변). 9~16 사이는 두 점 동일 → 상수.
	{"h": 9.0,  "sun_rot": Vector3(-52, -125, 0), "sun_col": Color(1, 1, 1),          "sun_e": 1.00, "amb_col": Color(0.78, 0.76, 0.82), "amb_e": 0.55},
	{"h": 16.0, "sun_rot": Vector3(-52, -125, 0), "sun_col": Color(1, 1, 1),          "sun_e": 1.00, "amb_col": Color(0.78, 0.76, 0.82), "amb_e": 0.55},
	# 노을 골든아워(가장 예쁠 시간대) — 따뜻한 주황·보라, 태양 지평선 근처 낮게.
	{"h": 18.0, "sun_rot": Vector3(-14, -125, 0), "sun_col": Color(1.00, 0.72, 0.42), "sun_e": 0.95, "amb_col": Color(0.85, 0.62, 0.52), "amb_e": 0.52},
	# 황혼 보라 → 밤으로 감광
	{"h": 19.5, "sun_rot": Vector3(-4, -125, 0),  "sun_col": Color(0.85, 0.52, 0.50), "sun_e": 0.42, "amb_col": Color(0.52, 0.44, 0.62), "amb_e": 0.45},
	{"h": 21.0, "sun_rot": Vector3(-58, -125, 0), "sun_col": Color(0.55, 0.62, 0.90), "sun_e": 0.18, "amb_col": Color(0.36, 0.40, 0.55), "amb_e": 0.40},
	{"h": 24.0, "sun_rot": Vector3(-58, -125, 0), "sun_col": Color(0.55, 0.62, 0.90), "sun_e": 0.18, "amb_col": Color(0.36, 0.40, 0.55), "amb_e": 0.40},
]

# 날씨 → 하늘 흐림. 조명 키프레임(위 KEYS)은 건드리지 않는다 — 비 분위기는 구름량과 빗줄기로만.
const CLOUD_CLEAR := 0.32   # sky.gdshader 기본값
const CLOUD_RAIN := 0.85
const CLOUD_RATE := 0.6     # 초당 전이량 (자정 날짜 전환 시 구름이 툭 튀지 않게)

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
	_sun.rotation_degrees = p["sun_rot"]
	_sun.light_color = p["sun_col"]
	_sun.light_energy = p["sun_e"]
	if _env != null:
		_env.ambient_light_color = p["amb_col"]
		_env.ambient_light_energy = p["amb_e"]
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("time_of_day", h)
		var cov_t := CLOUD_RAIN if GameData.is_rainy(GameClock.abs_day) else CLOUD_CLEAR
		_cov = cov_t if _cov < 0.0 else move_toward(_cov, cov_t, dt * CLOUD_RATE)
		_sky_mat.set_shader_parameter("cloud_coverage", _cov)

func _cache() -> void:
	_sun = get_node_or_null("../Sun") as DirectionalLight3D
	_env = get_viewport().get_world_3d().environment  # 런타임 생성 WorldEnvironment의 활성 env (이름 가정 없음)
	if _env != null and _env.sky != null:
		_sky_mat = _env.sky.sky_material as ShaderMaterial

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

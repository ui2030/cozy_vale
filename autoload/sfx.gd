extends Node
# 사운드 단일 창구 (DESIGN 11.x 오토로드 규약). 두 가지를 소유한다:
#   1) 효과음 — AudioStreamPlayer 풀 + 재생마다 피치 랜덤(같은 소리 반복해도 기계음 안 남).
#   2) 앰비언스 — 낮(새)·밤(귀뚜라미) 두 루프를 항상 재생하며 시각으로 등파워 크로스페이드.
# 시간은 GameClock 단일 권위에서만 읽는다(자기 시계 소유 금지). day_night.gd와 무관 — 조명은
# 조명대로, 소리는 소리대로 같은 game_min을 각자 읽는다.
#
# 음원은 preload가 아니라 런타임 load_from_file로 읽는다: 이 프로젝트는 임포트 파이프라인을
# 쓰지 않는다(GLB도 toon_character.load_glb가 GLTFDocument로 직접 읽음 — .import 파일 0개).
# 덕분에 assets/audio/sfx에 ogg를 떨구면 파일명이 곧 클립 이름이 된다. 출처는 CREDITS.md.

const SFX_DIR := "res://assets/audio/sfx"
const AMB_DIR := "res://assets/audio/ambience"

const POOL_SIZE := 8          # 동시 효과음 상한 (초과분은 무음 드롭 — 겹쳐도 귀에 안 띔)
const PITCH_JITTER := 0.06    # ±6% 피치 랜덤

var water_loop: AudioStream   # 물가 3D 에미터용 (world.gd가 빌려 씀)

# 헤드리스(--headless)면 더미 오디오 드라이버라 아무도 못 듣는다. 그런데도 재생을 걸면 ogg/mp3를
# 계속 디코드하고, 종료 시 믹스 스레드가 playback을 놓아주기 전에 ObjectDB 검사가 돌아
# "N ObjectDB instances were leaked at exit" 경고가 간헐적으로 뜬다. 그래서 재생만 건너뛴다
# (로드·볼륨·풀 관리는 그대로 — 로직은 헤드리스에서도 똑같이 돈다).
# world.gd의 물가 3D 에미터도 이 값을 보고 생성을 건너뛴다.
var silent := false

var _clips := {}              # 클립이름 → AudioStream
var _pool: Array[AudioStreamPlayer] = []
var _day: AudioStreamPlayer
var _night: AudioStreamPlayer
var _last_min := -1

# ── 앰비언스 곡선 (순수 함수, test_core 단위검증) ───────────────
# 시각 h(0~24) → 낮 가중치 0..1. 새벽 5~7시 상승, 낮 7~18시 1, 해질녘 18~20.5시 하강.
# day_night.gd의 조명 키프레임(6.5 새벽 / 18 노을 / 19.5 황혼)에 맞춰 둔 값 — 소리가 조명보다
# 급하게 바뀌면 어색하므로 램프 폭을 조명보다 넓게 잡았다.
static func day_weight(h: float) -> float:
	if h < 5.0 or h >= 20.5:
		return 0.0
	if h < 7.0:
		return (h - 5.0) / 2.0
	if h < 18.0:
		return 1.0
	return 1.0 - (h - 18.0) / 2.5

# 등파워(equal-power) 크로스페이드: 선형으로 섞으면 중간점에서 음량이 푹 꺼진다.
static func fade_db(weight: float) -> float:
	var w := clampf(weight, 0.0, 1.0)
	return -80.0 if w < 0.0001 else linear_to_db(sqrt(w))

# 버스 레이아웃이 없거나 이름이 어긋나도 로그 도배 없이 Master로 흐르게 (헤드리스 안전).
static func bus_or_master(bus: String) -> String:
	return bus if AudioServer.get_bus_index(bus) != -1 else "Master"

# 확장자로 스트림 종류를 갈라 읽는다. 실패하면 null(호출측이 조용히 건너뜀).
static func load_stream(path: String) -> AudioStream:
	if path.ends_with(".mp3"):
		return AudioStreamMP3.load_from_file(path)
	return AudioStreamOggVorbis.load_from_file(path)

# ───────────────────────────────────────────────────────────────
func _ready() -> void:
	silent = DisplayServer.get_name() == "headless"
	for f in DirAccess.get_files_at(SFX_DIR):
		var s := load_stream(SFX_DIR + "/" + f)
		if s != null:
			_clips[f.get_basename()] = s
	if _clips.is_empty():
		push_warning("Sfx: 효과음을 하나도 못 읽었다 — " + SFX_DIR)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = bus_or_master("SFX")
		add_child(p)
		_pool.append(p)
	water_loop = _looping(AMB_DIR + "/water_loop.ogg")
	_day = _ambience_player(AMB_DIR + "/bird_day.ogg")
	# ponytail: 귀뚜라미는 mp3 그대로(브리프 승인). LAME 인코더 패딩 탓에 루프 이음매에 수십 ms
	# 공백이 생길 수 있다 — 실제로 들리면 ogg로 재인코딩해 파일만 갈아끼우면 된다(코드 무변경).
	_night = _ambience_player(AMB_DIR + "/cricket_night.mp3")

func _looping(path: String) -> AudioStream:
	var s := load_stream(path)
	if s != null:
		s.loop = true
	return s

func _ambience_player(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _looping(path)
	p.bus = bus_or_master("Ambience")
	p.volume_db = -80.0
	add_child(p)
	if p.stream != null and not silent:
		p.play()
	return p

# 종료 시 재생 중이던 스트림을 놓아준다. 안 하면 playback 객체가 ObjectDB에 남아
# 헤드리스 테스트가 "instances were leaked at exit" 경고를 뱉는다(오토로드는 씬보다 늦게 죽는다).
func _exit_tree() -> void:
	for p in _pool + [_day, _night]:
		p.stop()
		p.stream = null
	_clips.clear()
	water_loop = null

# 시각이 바뀐 분에만 갱신. 신호 대신 폴링인 이유: tick은 PAUSED에서 멈추고 취침·세이브 로드는
# game_min을 신호 없이 점프시킨다 — 프레임당 정수 비교 하나가 그 경계들을 전부 덮는다.
func _process(_dt: float) -> void:
	if GameClock.game_min == _last_min:
		return
	_last_min = GameClock.game_min
	var w := day_weight(GameClock.game_min / 60.0)
	_day.volume_db = fade_db(w)
	_night.volume_db = fade_db(1.0 - w)

# ── 효과음 ─────────────────────────────────────────────────────
# 풀이 전부 바쁘면 조용히 버린다(소리 겹침 상한 = 클리핑·산만함 방지).
func play(clip: String, volume_db := 0.0) -> void:
	var stream: AudioStream = _clips.get(clip)
	if stream == null:
		push_warning("Sfx.play: 없는 클립 " + clip)
		return
	for p in _pool:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.pitch_scale = randf_range(1.0 - PITCH_JITTER, 1.0 + PITCH_JITTER)
			if not silent:
				p.play()
			return

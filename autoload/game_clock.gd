extends Node
# 유일 시간 권위 (DESIGN 11.2). 하위 시스템은 신호 구독만, 자기 달력 소유 금지.
# 고정 tick: _process는 실시간 accumulator만, 정수 game_min tick은 while로 (프레임드랍 안전).

signal tick(abs_day: int, game_min: int)
signal day_changed(prev_abs_day: int, abs_day: int)
signal season_changed(prev_season: int, season: int)

enum State { NORMAL, PAUSED, FAST }

const MINUTES_PER_DAY := 1440
const DAYS_PER_SEASON := 28
const SEASONS := ["봄", "여름", "가을", "겨울"]
const WEEKDAYS := ["월", "화", "수", "목", "금", "토", "일"]
const WAKE_MIN := 360  # 06:00

@export var real_seconds_per_day := 900.0  # 현실 15분 = 게임 하루
@export var fast_multiplier := 6.0

var abs_day := 0        # 시작일=0부터 단조증가 (계절/연차와 별개, 성장계산 기준)
var game_min := WAKE_MIN
var state: State = State.NORMAL
var _accum := 0.0

func _process(delta: float) -> void:
	if state == State.PAUSED:
		return
	var sec_per_min := real_seconds_per_day / float(MINUTES_PER_DAY)
	var mult := fast_multiplier if state == State.FAST else 1.0
	_accum += delta * mult
	while _accum >= sec_per_min:
		_accum -= sec_per_min
		_advance_minute()

func _advance_minute() -> void:
	game_min += 1
	if game_min >= MINUTES_PER_DAY:
		game_min = 0
		_advance_day()
	tick.emit(abs_day, game_min)

func _advance_day() -> void:
	var prev := abs_day
	var prev_season := season()
	abs_day += 1
	day_changed.emit(prev, abs_day)
	if season() != prev_season:
		season_changed.emit(prev_season, season())

# 취침: 항상 다음날 아침으로. clock만 갱신 + 신호 emit (저장은 호출측이 정산 후).
func sleep_to_morning() -> void:
	var prev := abs_day
	var prev_season := season()
	abs_day += 1
	game_min = WAKE_MIN
	_accum = 0.0
	day_changed.emit(prev, abs_day)
	if season() != prev_season:
		season_changed.emit(prev_season, season())

# 파생 (전부 abs_day에서 계산 — 어디에도 중복 저장 안 함)
# _at 변형은 임의의 abs_day용 순수 함수 — 날씨처럼 "오늘 말고 그날" 판정을 하는 쪽이
# 달력 수식을 자기 파일에 복제하지 않게 한다(시간 파생은 여기가 단일 출처).
static func season_at(d: int) -> int: return int(d / DAYS_PER_SEASON) % 4
static func day_of_season_at(d: int) -> int: return d % DAYS_PER_SEASON + 1

func season() -> int: return season_at(abs_day)
func day_of_season() -> int: return day_of_season_at(abs_day)
func year() -> int: return int(abs_day / (DAYS_PER_SEASON * 4)) + 1
func weekday() -> int: return abs_day % 7
func hour() -> int: return int(game_min / 60)
func minute() -> int: return game_min % 60

func to_dict() -> Dictionary:
	return {"abs_day": abs_day, "game_min": game_min}

func from_dict(d: Dictionary) -> void:
	abs_day = int(d.get("abs_day", 0))
	game_min = int(d.get("game_min", WAKE_MIN))
	_accum = 0.0

extends Node3D
# 마을 드레싱 (P3 1차) — 소품·꽃 덤불·숲 띠. **전부 무충돌 장식**이다.
# WORLD_VERSION 3 유지의 근거가 "데코는 통행·상호작용을 건드리지 않는다"이므로,
# ① 로드한 GLB에서 충돌체를 벗기고 ② 빌드 끝에 데코 루트 전체를 스캔해 로그로 증명한다.
#
# 에셋: Kenney Nature Kit 2.1 (CC0) — assets/props/*.glb. 이 repo 관례대로 Godot 임포트
# 파이프라인이 아니라 ToonChar.load_glb 런타임 로드(가구 전례: world/interior.gd).
# 킷 원본 색은 마을 팔레트와 다르므로 머티리얼 이름 → VILLAGE_SPEC §2 팔레트로 다시 칠한다.
#
# 툰 변환 순서: decor는 자체 변환한다(GLB=ToonChar.apply, 절차 메시=make_solid). world.gd의
# _convert_statics는 material_override가 StandardMaterial3D인 노드만 보므로 여기 것은 전부 스킵된다.

const ToonChar := preload("res://common/toon_character.gd")
const DayNight := preload("res://world/day_night.gd")  # 가로등 점등 시각 판정(단일 출처)
const WINDOW_SHADER := preload("res://world/window.gdshader")  # 등 유리 발광 판(창불빛과 공용)
const DIR := "res://assets/props/"
const OUTLINE := 0.006   # world.gd 정적물과 같은 연필선 두께
# 회관 파사드 등나무를 매달지 여부. world.gd가 build 전에 세운다 — 회관이 컬러박스가 아니라
# GLB 모델이면 매달 처마가 없다.
var hall_drapes := true
const GROUND_Y := 0.10   # 지면 상면 (world.tscn Ground / beach.gd GROUND_Y와 동일)

# ── 구매/CC0 킷 (베이크된 albedo 텍스처가 있는 에셋) ─────────────────
# Kenney 킷은 머티리얼이 단색이라 _repaint로 마을 팔레트에 다시 칠했지만, 이쪽은 **텍스처
# 아틀라스**를 쓴다. ToonChar.apply가 원본 머티리얼의 albedo_texture를 그대로 toon 셰이더의
# use_tex/albedo_tex로 넘기므로(단색 경로와 같은 함수) 텍스처를 죽이지 않고 툰 라이팅·외곽선·
# 월드 곡률이 전부 걸린다 → 재도색하지 않는다. MAT_COLORS에 없는 이름이라 _repaint도 안 탄다.
const TT_PARK := "res://assets/tinytreats/Tiny_Treats_Pretty_Park_1.0_FREE/Assets/gltf/"
const VENDOR := "res://assets/vendor/plumberry-plains-props-vol-1/props/"
# 밝기만 마을 규약에 맞춘다. 킷 아틀라스의 UV가 실제로 닿는 텍셀 최댓값이 0.83~0.97(sRGB)인데,
# 정오 직광면은 albedo 0.745를 넘으면 화면에서 255로 클리핑한다(world.gd C_GRASS 주석의 실측
# 계수 1.93 = 지면 albedo 0.75 상한의 출처). char_tint는 선형 공간 곱이라 텍셀 1.0 → 이 색의
# sRGB 값이 그대로 상한이 된다 = interior.gd TINT_DEF(Kenney 순백 1.0 → 0.72)와 같은 수법.
const KIT_TINT := Color(0.76, 0.75, 0.72)
# 밝기를 맞춰도 **채도**가 남는다 — (max−min)/max: 마을 팔레트 상수가 벽토 0.11 · 최고치인
# 보라 기와 0.33인데 화면 실측이 TT 벤치 좌판 0.69 · Plumberry 게시판 기와 0.85로, 형태는 맞아도 색이
# "다른 게임 스티커"로 읽혔다(assets1/after_hall_h12). 아틀라스를 다시 굽지 않고 toon 셰이더의
# 채도 상한(sat_cap)으로 깎는다. 선형 albedo 0.60 = 같은 컷 화면 실측 게시판 기와 0.42 ·
# 벤치 좌판 0.49로, 마을 보라 기와 0.41 · 화분 목재 0.50과 같은 대역(assets2 실측표).
# 상한을 넘는 텍셀만 깎이므로 이미 얌전한 부분(판넬 종이·석재)은 원본 그대로 = 디테일 보존.
const KIT_SAT_CAP := 0.60

# ── 팔레트 (VILLAGE_SPEC §2, 낮 기준 — world.gd 상수와 같은 값) ──────
# 파스텔 시프트(소프트닝 v1) — world.gd와 같은 규칙·같은 값(채도 −15%p / ×0.55 하한, 명도 +5%p).
const C_WOOD   := Color(0.590, 0.480, 0.362)  # 브라운
const C_WOOD_D := Color(0.470, 0.372, 0.283)  # 목재 음영
const C_STONE  := Color(0.770, 0.758, 0.735)
const C_CREAM  := Color(0.742, 0.727, 0.690)  # 크림 (world.gd C_WALL과 같은 값 — 그쪽 주석이 처방)
const C_ROOF   := Color(0.509, 0.429, 0.610)  # 보라 진
# 풀포기·덤불. 옛 (0.652,0.710,0.494)는 채도 0.30·R/G 0.92의 카키라, 얇은 판때기 지오메트리가
# 정오 직광을 받으면 (210,225,160)쯤으로 떠서 초지 위에 노란 종이조각이 흩어진 것처럼 보였다.
# 채도를 0.21로 내리고 R을 낮춰(R/G 0.86) 초지(0.627,0.720,0.576)의 한 단 깊은 초록으로 맞춘다.
const C_GREEN  := Color(0.552, 0.645, 0.508)  # 그린 (풀·덤불)
const C_LEAF   := Color(0.576, 0.650, 0.444)  # 활엽 수관 — 지면(0.627,0.72,0.576)보다 깊게
const C_CONIF  := Color(0.509, 0.600, 0.439)  # 침엽수(어두운 그린)
const C_YELLOW := Color(0.880, 0.776, 0.432)  # 개나리
const C_LAV    := Color(0.656, 0.572, 0.740)  # 라벤더/보라 중
const C_LILAC  := Color(0.840, 0.758, 0.840)  # 라일락
const C_WIST   := Color(0.720, 0.649, 0.790)  # 등나무 보라
const C_GLASS  := Color(1.00, 0.90, 0.62)  # 가로등 유리(옐로 창불빛)
# ── 겨울 서리 톤 기준값 ────────────────────────────────────────────
# 식생이 킷 텍스처로 바뀌면서 이 두 색을 **직접 칠하지는 않는다**(단색으로 덮으면 겨울에만 다시
# 통짜가 된다). 대신 FLORA_WINTER_* / TREE_WINTER_GAIN을 **이 두 톤의 화면값에 맞춰 튜닝**했다 —
# 즉 여전히 겨울 룩의 기준점이고, 둘 사이 서열은 test_core가 박아둔다. C_FROST는 에셋 누락 폴백에도 쓴다.
#
# 서리 앉은 마른 풀. 눈 지면(world.gd C_SNOW 0.66~0.71)보다 확실히 아래여야 실루엣이 읽힌다 —
# 비슷한 값으로 두면 흰 바탕에 흰 낙서가 되어 풀포기가 사라진다(실측).
# 옛 (0.48,0.54,0.56)은 B>R인 청록이라 얇은 판 지오메트리가 "유리조각"으로 읽혔다(실측
# audit2/winter_hall_h12). 명도는 그대로 두고 색상만 마른 풀 쪽(R>G>B)으로 돌린다 —
# 눈 지면과의 대비(≈0.14)는 유지되므로 실루엣 근거가 안 바뀐다.
const C_FROST  := Color(0.58, 0.55, 0.49)
# 수관용 서리톤은 풀포기용보다 훨씬 밝다. 풀은 흰 눈 지면 위에 놓여 어두워야 읽히지만, 수관은
# 크림 하늘을 배경으로 서 있어서 C_FROST를 쓰면 화면에 (113,124,142)로 나와 눈 덮인 나무가
# 아니라 바위 덩어리로 보인다(실측). 눈 지면(0.66/0.68/0.71) 바로 아래 = 가지에 얹힌 눈.
const C_FROST_LEAF := Color(0.62, 0.65, 0.69)

# Kenney 머티리얼 이름 → 마을 팔레트. 없는 이름은 원본색 유지 + 로그로 알린다.
const MAT_COLORS := {
	"leafsGreen": C_LEAF, "leafsDark": C_CONIF, "grass": C_GREEN,
	"woodBark": C_WOOD, "woodBarkDark": C_WOOD_D, "wood": C_WOOD, "woodDark": C_WOOD_D,
	"dirt": C_STONE, "colorYellow": C_YELLOW, "colorPurple": C_LAV, "_defaultMat": C_CREAM,
}

# ── 데코 금지 존 (Codex MUST-FIX 2) ─────────────────────────────────
# 기능(통행·상호작용·연출)을 침범하면 안 되는 곳. 소품·꽃·나무 전부 이 판정을 통과해야 한다.
const NO_DECOR_CIRCLES := [
	[Vector2(0, 0), 2.4],        # 분수 (충돌 r1 + 접근 여유)
	[Vector2(0, -6), 4.0],       # 축제·결혼 집합 링 (FEST_RING 2.3 / 축제 장식 DECOR_RING 3.3)
	[Vector2(0, -3.5), 2.2],     # 기본 스샷 지점 (world.gd festival/hour 인자)
	[Vector2(10, 0), 4.6],       # 연못(수면 r2.5) + 낚시 프롬프트 지점(10,3.8)
	[Vector2(-5, -5), 2.2],      # 상점 카운터 (프롬프트)
	[Vector2(9.5, 7), 2.0],      # 판매 상자 (프롬프트)
	[Vector2(3, 18.3), 2.6],     # 플레이어 집 문 트리거 (Interior.OUT_DOOR)
	[Vector2(3, 20.6), 2.6],     # 집에서 나오는 자리 (Interior.OUT_SPAWN)
	[Vector2(29, -24), 4.0],     # 풍차 대지
	[Vector2(29, -18.5), 4.0],   # 풍차 램프
]
# 건물 footprint + 0.6 패드 [중심, 반폭x, 반폭z]
const BUILDINGS := [
	[Vector2(0, -18), 3.6, 3.1], [Vector2(-20, -14), 2.6, 2.6], [Vector2(-24, 2), 2.6, 2.6],
	[Vector2(-14, 22), 2.6, 2.6], [Vector2(24, 20), 2.6, 2.6], [Vector2(-7, -7), 2.1, 2.1],
	[Vector2(3, 15), 3.1, 3.1], [Vector2(-26, 14), 2.6, 2.6],
]
const FARM := Rect2(-0.8, 1.2, 9.6, 5.6)          # 밭 타일 x[0,8] z[2,6] + 0.8 (farm_system.REGION)
const CAM_LANE := Rect2(-2.0, -4.5, 4.0, 12.0)    # 스샷 카메라(플레이어 +z9.5)와 광장 사이 시선
const BEACH_LANE := Rect2(20.0, 21.0, 8.0, 20.0)  # 해변 접근로 + 게이트(24,32.5)·스폰(24,29.4)
const ROAD_KEEP := 1.9      # 길 중심선(폭 2.4)에서 비우는 거리
const RIVER_KEEP := 3.0     # 강 중심선 (npc_system RIVER_AVOID 2.9와 정합)
const BRIDGE_KEEP := 4.5    # 다리 데크 + 진입로

# 식생 전용 추가 금지(기능이 아니라 그림 문제 — NPC가 꽃밭에 서 있지 않게)
const NPC_ANCHORS := [  # npc_system.ANCHORS
	Vector2(-4.5, 3.5), Vector2(-3.5, -3.5), Vector2(12, -3.5),
	Vector2(13, 6.2), Vector2(27, -12), Vector2(3, 10.5),
]
const NPC_HOMES := [  # data/npcs.json home 9곳
	Vector2(-20, -9), Vector2(22, 17), Vector2(-19, 20), Vector2(-6, 19), Vector2(-24, -3),
	Vector2(-15, -11), Vector2(-8, 6), Vector2(-8, -4), Vector2(-22, 10),
]
const ANCHOR_KEEP := 3.6    # ANCHOR_R_MAX 3.0 + 여유
const HOME_KEEP := 4.5      # 집 앞 정지·배회 중심
const PLAZA_R := 6.4        # 광장 판석 위엔 식생 금지(판석이 보여야 한다)
# ── 식생 = Tiny Treats Pretty Park 킷 모델 (CC0) ─────────────────────
# 절차 메시(blob_mesh 수관·BUSH_BLOB 덤불·_rosette 꽃)를 전부 버렸다. 유저 판정:
# "너무 통짜야. 난 디테일을 원해" — 절차 폐곡면은 단색 덩어리 하나라 어느 각도에서도 실루엣이
# 하나뿐이고, 킷 모델은 잎·꽃잎·꽃심·수피가 아틀라스에 구워져 있어 근경에서 형태가 갈린다
# (참고 이미지: 동물의 숲 꽃밭 — 종류별로 꽃잎·중심부가 뚜렷이 구분된다).
#
# 종별 배율 [최소, 최대]. 원본 전고가 제각각이라 한 배율로 묶으면 풀포기가 갈대가 된다.
# 근거는 전부 **옛 절차 전고 대역을 그대로 계승**한 값 — 배치 밀도·금지 존이 그 크기 전제로
# 승인돼 있어서 크기를 바꾸면 화단이 통째로 다시 튜닝 대상이 된다.
# 꽃만 예외다: 킷 꽃은 줄기 위 한 송이가 아니라 **납작하고 넓은 지피 꽃**(native 0.45폭 × 0.14고)이라
# 옛 전고(0.46~0.65)를 맞추면 폭이 1.5m짜리 괴물이 된다. 그래서 전고가 아니라 34° 카메라의
# **투영 면적**을 맞춘다: 옛 꽃 0.30폭×0.55고의 투영이 ≈0.17㎡ = 킷 배율 1.0 지점.
const FLORA_SCALE := {
	# 꽃 배율은 두 번 실측했다. 1차(1.20~1.70 / 1.35~1.90 = 투영 면적 등가)는 근경에선 좋았지만
	# 광장 화단 링 거리(카메라 ~20)에서 흰 점으로 흩어져 "꽃밭"이 안 읽혔다(after_life_h12) —
	# 납작한 지피 꽃은 거리가 붙으면 투영 높이가 먼저 죽는다. 그래서 한 단 더 키운 값이 아래다.
	"flower_A":   Vector2(1.55, 2.15),  # native 0.138고/0.45폭 → 0.21~0.30고 · 0.70~0.97폭 (데이지+노란 꽃심)
	"flower_B":   Vector2(1.75, 2.45),  # native 0.111고/0.31폭 → 0.19~0.27고 · 0.55~0.76폭 (푸른 꽃)
	"bush":       Vector2(0.75, 1.10),  # native 0.538 → 0.40~0.59 (옛 덤불 0.38~0.57)
	"bush_large": Vector2(0.55, 0.80),  # native 0.759 → 0.42~0.61
	"grass_A":    Vector2(0.85, 1.25),  # native 0.402 → 0.34~0.50 (옛 풀 0.33~0.50)
	"grass_B":    Vector2(0.90, 1.35),  # native 0.406 → 0.37~0.55
}
# 킷 식생 아틀라스는 마을 파스텔보다 훨씬 어둡다 — 수관 화면 실측 (72,128,76) vs 옛 절차 수관
# (195,212,169). 218그루를 그대로 심으면 파스텔 마을에 진초록 숲이 붙여넣기 된 것처럼 읽힌다.
# toon 셰이더 val_gain(순수 곱, hue·비율 보존)으로 마을 대역까지 끌어올린다. 값은 실측 튜닝.
const VEG_GAIN := 1.85
# 종별 색조 곱(없으면 KIT_TINT). 파크 킷 꽃은 **흰 데이지(flower_A)와 푸른 꽃(flower_B) 두 색뿐**이라
# 그대로 심으면 마을 화단의 노랑(C_YELLOW)이 통째로 사라진다 — 중경이 눈에 띄게 비어 보였다
# (실측 before/after_life_h12 대조: 옛 노랑·보라 점들이 흰 티끌로 바뀜).
# 흰 꽃잎은 **곱으로 색을 입힐 수 있다**: KIT_TINT × (C_YELLOW를 최대 채널로 정규화한 비율)
# = (0.760, 0.662, 0.354). 밝기 천장(KIT_TINT가 잡아둔 정오 클리핑 상한)은 그대로 두고 색상만 준다.
# 다만 **끝까지 주면 안 된다**: flower_A는 흰 꽃잎 + 노란 꽃심이라, 완전 노랑을 곱하면 둘이 같은
# 색으로 붙어 꽃심이 사라지고 노란 덩어리가 된다(실측 근접 크롭) — 유저가 원한 "꽃잎·중심부 구분"의
# 정반대다. KIT_TINT에서 완전 노랑 쪽으로 0.70만 간다 = 꽃잎은 버터색, 꽃심은 한 단 진한 호박색.
# 푸른 꽃은 곱으로 보라가 못 된다(R 텍셀 자체가 없다) → 원색 유지 = 연못·하늘과 같은 계열의 시원한 악센트.
#
# 그리고 **한 가지 색으론 부족하다**. 유저가 붙인 참고 이미지(동물의 숲 꽃밭)의 요점은 꽃잎
# 디테일만이 아니라 **종류가 여럿이라는 것**이었다 — 노란 꽃만 깔면 색이 하나인 화단이다.
# 킷엔 꽃 메시가 둘뿐이지만 flower_A는 **흰 꽃잎**이라 곱으로 어느 색이든 낼 수 있다. 그래서
# 같은 메시를 색만 달리한 변종(`flower_A~white`, `flower_A~pink`)으로 나눈다. 이름의 `~` 앞이
# 킷 파일명이다. MultiMesh는 인스턴스별 색을 안 쓰므로 **색을 가르려면 버킷을 가르는 수밖에
# 없다** = 변종 하나당 드로우콜 +1. 꽃 2색 → 4색에 +2로 산다.
# (푸른 flower_B는 변종을 못 만든다 — R 텍셀이 0이라 곱으로는 파랑 계열 밖으로 못 나간다.)
# 분홍값은 노랑과 같은 유도식이다: KIT_TINT에서 (0.85,0.45,0.55)를 최대 채널로 정규화한
# 비율 쪽으로 0.70만 간다 = 꽃잎은 분홍, 꽃심은 한 단 진한 장미색으로 갈린다.
#
# **라벤더는 마을 정체색이다**(VILLAGE_SPEC §2: 개나리 노랑 + 라벤더). 그런데 킷 전환 때
# 조용히 빠져 있었다 — C_LAV 상수는 남았는데 심기는 노랑·분홍·흰색·파랑뿐이라, "라벤더가
# 가득한 마을"에 라벤더가 한 포기도 없었다. 푸른 flower_B로는 못 메운다(위 주석: R 텍셀 0).
# 유도식은 노랑·분홍과 같다. 다만 목표색으로 C_LAV(0.656,0.572,0.740)를 쓰면 그 자체가 옅어
# 결과가 회보라로 죽는다 — 원거리에서 흰 꽃과 구분이 안 된다. 확실히 보라인 (0.62,0.42,0.85)를
# 목표로 잡아 분홍과 같은 세기로 맞춘다(최대 채널 0.720 < 정오 클리핑 상한 0.75).
const FLORA_TINT := {
	"flower_A": Color(0.760, 0.688, 0.464),          # 노랑 — 옛 마을 화단의 C_YELLOW 계승
	"flower_A~pink": Color(0.760, 0.503, 0.542),     # 분홍
	"flower_A~lavender": Color(0.616, 0.485, 0.720), # 라벤더 — 마을 정체색
	# "flower_A~white"는 여기 없다 = KIT_TINT 그대로 = 킷 원본 흰 데이지.
}
# 실제로 심는 버킷 목록 = MultiMesh 목록. `~` 뒤는 색 변종이라 메시는 같다.
const FLORA_BUCKETS := ["flower_A", "flower_A~white", "flower_A~pink", "flower_A~lavender",
	"flower_B", "bush", "bush_large", "grass_A", "grass_B"]

# 버킷 이름 → 킷 파일명 (색 변종 접미 제거)
static func kit_of(nm: String) -> String:
	var i := nm.find("~")
	return nm.substr(0, i) if i >= 0 else nm
# ── 겨울 서리 (텍스처를 죽이지 않고 채도만 지우고 밝기를 올린다 = 잎 결이 남은 "얹힌 눈") ──
# 옛 방식(albedo를 C_FROST/C_FROST_LEAF 단색으로 교체)을 그대로 쓰면 겨울에만 다시 통짜가 된다.
# **나무와 지피 식생은 밝기 목표가 반대다** — 옛 두 상수(C_FROST_LEAF vs C_FROST)가 갈려 있던 이유:
#   수관은 크림 하늘을 배경으로 서 있어 밝아야 눈 덮인 나무로 읽힌다(어두우면 바위 덩어리).
#   풀포기는 흰 눈 지면 위에 놓여 **확실히 어두워야** 실루엣이 남는다(비슷하면 흰 바탕의 흰 낙서).
# 1차 실측에서 둘을 같은 값(2.6)으로 묶었더니 정확히 그 실패가 났다: 서리 풀 화면 (209,198,189)이
# 설원 (213,215,220)에 붙어 중경이 통째로 비었다 — 옛 값은 (166,164,133)이었다.
const VEG_WINTER_SAT := 0.06
const TREE_WINTER_GAIN := 2.35   # 수관 목표 = 옛 C_FROST_LEAF 화면값 (236,239,244)
const FLORA_WINTER_GAIN := 2.15  # 지피 목표 = 옛 C_FROST 화면값 (166,164,133) 대역
# 서리 풀은 청록이 아니라 **마른 풀**이어야 한다(옛 C_FROST 주석: B>R 청록은 "유리조각"으로 읽혔다).
# KIT_TINT × C_FROST를 최대 채널로 정규화한 비율 = 명도 천장은 그대로, 색상만 R>G>B로 돌린다.
const FLORA_WINTER_TINT := Color(0.760, 0.711, 0.608)
# ── 가을 단풍 (겨울 서리와 **같은 처방**: 채도를 지우고 → 밝히고 → 색을 준다. 단 **잎만**) ──
# 킷 잎 텍셀은 초록이다(실측 sRGB (0.294,0.639,0.373)). 여기에 주황을 곱하기만 해서는 단풍이
# 안 된다: R을 G 위로 올리려면 R/G 비를 3배 넘게 밀어야 하는데, 그 배율이면 G가 셰이더의
# min(src*gain, 1.0)에 잘려 잎 텍셀이 전부 같은 값으로 붙는다 = 잎 결이 통째로 날아간 통짜(계산).
# 그래서 서리 사본과 같은 순서로 간다 — 채도 상한으로 잎을 거의 무채색 중간톤(실측 (0.584,0.629,0.593))
# 으로 만든 뒤 색조를 입힌다. 잎 결은 텍셀별 **명도차**로 남는다(잎 텍셀 최대채널
# 0.549~0.733 = 1.9배 폭이 그대로 살아있다).
# 표면이 하나라 예전엔 줄기까지 같이 주황으로 물들었다(스크린샷 실측 autumn_fix/before_forest_h12:
# 줄기 (218,117,58) vs 수관 (181,105,47) = 같은 주황 막대. 고친 뒤 줄기 (202,134,103) = 여름 줄기
# (189,138,110)과 같은 자리, 수관은 (180,105,47)로 무변경).
# ArrayMesh를 가르는 대신 셰이더가 **색으로** 가른다(toon.gdshader green_gate) — 단풍 사본은
# sat_cap·char_tint를 **킷 기본값 그대로** 두고(= 줄기가 사계절 같은 색), 잎 텍셀만
# leaf_sat·leaf_tint로 덮는다. 그래서 아래 두 값은 이제 **잎 전용**이다.
# 문턱 0.02는 아틀라스 실측 공백(수피 −0.317~−0.254 / 잎 +0.079~+0.392)의 안쪽 0 근처다.
# 두 값 다 최대채널이 정오 클리핑 상한 0.75 아래다(지면 핀과 같은 천장 — 넘으면 255로 포화).
# 화면 실측 환산(정오 = 선형 ×1.90): 수관 (211,154,89) = 크림 하늘을 배경으로 읽히는 따뜻한 주황.
const TREE_AUTUMN_SAT := 0.18
const TREE_AUTUMN_GAIN := 1.90
const TREE_AUTUMN_TINT := Color(0.831, 0.552, 0.326)
# 단풍 사본이 얹는 셰이더 파라미터 한 벌. val_gain은 잎·수피가 함께 탄다(1.90 vs 여름 1.85 =
# 줄기가 2.7% 밝을 뿐, 화면에서 1/255 수준).
const TREE_AUTUMN_EXTRA := {
	"green_gate": 0.02, "leaf_sat": TREE_AUTUMN_SAT, "leaf_tint": TREE_AUTUMN_TINT,
}
# ── 가을 지피(덤불·풀) — 겨울 서리와 **같은 구조**: 공용 override 한 장(드로우콜 추가 0) ──
# 가을에도 원색 초록으로 남아 있어서, 주황 나무 아래 형광 초록 덤불이 계절을 반만 온 것처럼
# 보였다(스크린샷 실측 autumn_fix/before_forest_h12: 덤불 (162,236,130) → 고친 뒤 (156,181,60)).
# **주황으로 밀면 안 된다.** 가을 화면엔 이미 주황·노랑이 넷이다(수관·낙엽·지면·꽃) — 덤불까지
# 같은 계열로 보내면 화면이 한 색으로 뭉개져 깊이가 죽는다. 목표는 "단풍든 덤불"이 아니라
# **"물기가 빠진 덤불"** = 올리브/황록. 지면에서 한 단 진하고, 낙엽·수관과는 확실히 갈리는 자리.
# 화면 실측 환산(정오 = 선형 ×1.90, 아틀라스 정점 UV 전수. test_core가 같은 식으로 다시 잰다):
#   덤불 (153,173,87) · 풀 (141,160,82)  ← 여름 원색 덤불 (148,216,143)
#   지면 (208,218,142) · 낙엽 (238,150,92) · 수관 (219,159,88)
#   (환산값은 자기 그림자가 없는 평면 기준이라 스크린샷보다 조금 밝다 — 덤불 실측 (156,181,60).)
#   화면 거리(정규화 RGB): 덤불↔수관 0.265 · 덤불↔낙엽 0.344 · 덤불↔지면 0.349
#   (수관↔낙엽 0.082는 승인된 기존 쌍 — 둘은 일부러 붙어 있다. 그래서 대비 핀은 덤불 쪽만 잰다.)
# 덤불과 풀은 0.073밖에 안 떨어져 한 장을 공유한다(겨울 서리와 같은 판단).
# 최대 채널 0.623 < 정오 클리핑 상한 0.75.
const FLORA_AUTUMN_SAT := 0.22   # 잎 결을 명도차로 남길 만큼만(겨울 0.06까지 지우면 통짜)
const FLORA_AUTUMN_GAIN := 1.70  # 여름 1.85에서 한 단 어둡게 = 물기가 빠진 쪽
const FLORA_AUTUMN_TINT := Color(0.613, 0.623, 0.347)
const WALK_HALF := 33.0     # 초지 스프링클 범위(숲 띠 안쪽)

# ── 소품 배치표 [종류, x, z, yaw(도)] ────────────────────────────────
# 광장 각도는 방사 6갈래 길 사이 빈 구간을 골랐다(빌드 로그가 위반을 잡는다).
const PROPS := [
	# 가로등 — 광장 림 4(길·축제링·카메라 시선 사이 빈 구간) + 길목 4
	["lamp", 5.38, -1.54, 0], ["lamp", -5.35, -0.75, 0],
	["lamp", -3.98, 3.34, 0], ["lamp", 4.13, -6.61, 0],
	["lamp", 13.43, 3.15, 0],   # 동 다리 진입로
	["lamp", -9.50, -4.25, 0],  # 상점 앞
	["lamp", 6.60, 12.60, 0],   # 플레이어 집 가는 남길
	["lamp", 2.60, -14.60, 0],  # 회관 앞
	# 벤치 — 광장 2(분수 향) + 강변 1(다리 향) + 정자 양옆 2
	["bench", 4.30, 0.91, -102], ["bench", -3.21, -3.57, 42],
	["bench", 12.40, 8.60, 109], ["bench", -29.20, 14.00, 90], ["bench", -22.80, 14.00, -90],
	# 표지판 — 길목(판면이 광장을 향하도록 yaw)
	["sign", 6.89, -3.66, -62], ["sign", -7.42, -2.41, 72],
	["sign", 3.40, -9.00, -21], ["sign", -3.80, 9.60, 158],
	# 화분 — 상점 앞 1 + 집 앞 2 + 회관 앞 1
	["planter", -4.60, -9.60, 0], ["planter", 0.20, 18.20, 0],
	["planter", 5.80, 18.20, 0], ["planter", -2.60, -14.60, 0],
	# 꽃수레 — 상점 앞
	["cart", -8.20, -9.15, 25],
]
# 나무 울타리 [시작, 끝] — 막힌 구간의 기둥은 건너뛴다(그 자리가 자연스러운 출입구가 된다)
const FENCES = [
	[Vector2(3.4, 7.2), Vector2(8.6, 7.2)],       # 밭 남쪽(길·판매상자 비켜)
	[Vector2(-0.2, 12.8), Vector2(-0.2, 17.6)],   # 플레이어 집 앞마당 서
	[Vector2(6.4, 13.0), Vector2(6.4, 17.6)],     # 플레이어 집 앞마당 동
	[Vector2(2.3, -8.5), Vector2(2.3, -14.5)],    # 회관 북길 동측
	[Vector2(-2.3, -8.5), Vector2(-2.3, -14.5)],  # 회관 북길 서측
	[Vector2(11.4, 9.6), Vector2(11.4, 14.4)],    # 동 다리 남측 강변 난간
	[Vector2(14.6, 3.6), Vector2(14.6, 0.0)],     # 동 다리 북측 강변 난간
	[Vector2(13.79, -13.86), Vector2(18.05, -16.85)],  # 북동 다리 진입부
	[Vector2(-29.4, 10.6), Vector2(-22.6, 10.6)], # 정자 마당 북
	[Vector2(-29.4, 17.4), Vector2(-22.6, 17.4)], # 정자 마당 남
]
const FENCE_S := 2.6        # fence_simple 원본 1.0 → 높이 0.35×2.6 = 0.91 (캐릭터 2.1의 절반)

# ── 가로등 (밤에만 점등 — interior.gd 전례: DayNight.night_factor 단일 출처) ──
# 옛 값(에너지 1.1 · 반경 8.0 · 감쇠 1.0)은 등불 하나가 지름 15의 잔디를 고르게 덮어서
# "마을 전체가 살짝 밝은 밤"이 됐다 — 등 발치에 빛 웅덩이가 안 생기니 등이 켜졌는지도 모른다
# (실측 nightlife/before_open_pav_h21: 광장 전면이 균일 조도).
#
# 웅덩이는 **반경이 아니라 감쇠 지수로** 만든다. 반경을 8.0→6.5로 조였더니 웅덩이는 생겼지만
# 광구 경계가 벽을 가로지르는 자리에서 Forward+ 클러스터 격자가 그대로 드러나 벽에 계단 모양
# 블록이 찍혔다(실측 probe_e11_r65_a10 = 발생 / probe_e24_r80_a10·probe_e11_r80_a16 = 없음).
# 그래서 반경은 오히려 9.0으로 넉넉히 두고(경계에선 이미 광량 ≈0), 감쇠 2.4로 발치에 모은다:
# 등 발치 1.13(옛 0.69의 1.6배) · 광장 한복판 0.74(옛 1.0) — 발치:한복판 대비가 2.8배에서
# 6.1배가 된다 = 웅덩이는 생기고 광장은 여전히 따뜻하다(감쇠 3.0은 한복판이 청회색으로 식었다).
# **새 광원 0개** — 개수·비용 불변, 파라미터만 바뀐다.
#
# 그런데 에너지 3.0 × 감쇠 2.4는 **근거리에서 터진다**. 감쇠 지수는 거리에 대한 거듭제곱이라
# 등 발치(3.0)보다 가까운 면은 기하급수로 밝아지는데, 회관·상점 벽은 등에서 1~2밖에 안 떨어져 있다
# → 벽이 (255,255,233)로 클리핑, 등불 유리(242)보다 **벽이 더 밝았다**(실측 night2/before_hall_h21).
# 광원이 빛나는 게 아니라 벽에 흰 얼룩이 묻은 것처럼 읽힌 원인이 이것.
# 지수를 낮춰 근거리 첨두를 깎고(2.4→1.4) 에너지를 함께 내린다(3.0→0.55). 발치 웅덩이는 밤 환경광이
# 0.66배로 같이 내려가므로 상대 대비로 유지된다 — 웅덩이를 없애는 게 아니라 벽 클리핑만 걷어낸다
# (실측: 광장 웅덩이 대비가 옛 25단 → 31단으로 오히려 벌어졌다, night2/*_open_res_h21).
const LAMP_E := 0.55
const LAMP_RANGE := 9.0
const LAMP_ATT := 1.4      # omni_attenuation (1.0=선형) — 클수록 코어가 조이고 변두리가 빨리 죽는다
# 등 기둥·등갓 전용 렌더 레이어. 세진 등불이 코앞(0.02)의 제 등갓을 때리면 크림 유리가
# 흰색, 보라 갓지붕이 분홍으로 탄다(실측 probe_r90a30_pav). 광원 cull_mask에서 이 레이어만 빼면
# 등갓은 태양·환경광으로만 칠해져 낮 룩 그대로다(카메라 cull_mask는 전 레이어라 보이는 건 불변).
const LAMP_LAYER := 2
const ALL_LAYERS := 0xFFFFF

var _cache := {}                       # glb 이름 → 원본 노드(반복 로드 방지)
var _lights: Array[OmniLight3D] = []
var _glow: ShaderMaterial              # 가로등 유리 발광 판 공용 머티리얼 (_glow_mat)
var _frost: ShaderMaterial             # 겨울 식생 서리 override 공용 머티리얼 (_frost_mat)
var _autumn: ShaderMaterial            # 가을 지피 톤 override 공용 머티리얼 (_autumn_mat)
var _atlas: Texture2D                  # 파크 킷 아틀라스 — 전 식생이 공유(서리 머티리얼이 재사용)
var _blooms: Array[Node3D] = []        # 겨울에 숨길 만개 노드(화분·꽃수레 꽃, 등나무 드레이프 루트)
var _tree_mesh := {}                   # 활엽수 MMI 이름 → [원색, 겨울 서리, 가을 단풍] (tree_variant_index 계약)
var _flora_cache := {}                 # 식생 종 이름 → Mesh (MultiMesh·화분 꽃 공용)
var _unknown_mats := {}                # 팔레트에 없는 킷 머티리얼 이름(로그용)
# 검증 전용: 탑다운 도식용 좌표 수집 (headless는 MultiMesh 버퍼를 되읽지 못해 원본을 따로 남긴다)
var _dumping := "decordump" in OS.get_cmdline_user_args()
var _mm_pts := {}
var _n_props := 0
var _n_flora := 0
var _n_trees := 0

# world.gd가 _build_village 안에서(= _convert_statics 이전에) 호출한다.
# 강·다리·길 좌표는 world.gd에서 인자로 받는다(양방향 preload = 순환 참조 방지).
var _river: Array[Vector2] = []
var _bridges: Array[Vector2] = []
var _roads: Array = []  # [Vector2 a, Vector2 b]

func build(river_pts: Array, bridges: Array, roads: Array) -> void:
	add_to_group("decor")  # world.gd _apply_season이 계절 전환·로드 때 호출
	for p in river_pts:
		_river.append(p)
	for b in bridges:
		_bridges.append(b)
	for r in roads:  # [중심, 길이(로컬+Z), y회전(도)] → 선분 양 끝점
		var d := Vector2(sin(deg_to_rad(r[2])), cos(deg_to_rad(r[2]))) * (float(r[1]) * 0.5)
		_roads.append([r[0] - d, r[0] + d])
	_roads.append([Vector2(24, 23.0), Vector2(24, 34.0)])  # beach.gd _village_path 흙길

	_place_props()
	_place_fences()
	_place_flora()
	_place_leaf_litter()  # 전용 rng — 공용 스트림 위치를 안 건드린다(_place_forest 배치 보존)
	_place_forest()
	_wisteria()
	_audit()

# ══ 에셋 로드 ══════════════════════════════════════════════════════
func _glb(nm: String) -> Node3D:
	if not _cache.has(nm):
		var n := ToonChar.load_glb(DIR + nm + ".glb", OUTLINE)
		if n == null:
			return null
		_strip_collision(n)   # MUST-FIX 1: 킷엔 없지만 방어적으로 먼저 벗긴다
		_repaint(n)
		_cache[nm] = n
	return (_cache[nm] as Node3D).duplicate() as Node3D

# 텍스처 킷 로드 (전체 res:// 경로 + 배율 확정). world.gd 분수도 이걸 쓴다 = 킷 규약 단일 출처.
# 외곽선 두께는 오브젝트 공간이라 배율로 나눠 넣어야 월드에서 굵기가 일정하다
# (ToonChar.set_outline_width 주석의 규약 — 기존 _glb는 이 보정이 없어 sign이 ×3.6만큼 굵었다).
static func load_kit(path: String, sc: float, outline := OUTLINE, gain := 1.0) -> Node3D:
	var n := ToonChar.load_glb(path, outline / sc, KIT_TINT)
	if n == null:
		return null  # 에셋 누락(vendor는 gitignore) 폴백: 그 자리만 빈다
	_grade_kit(n, gain)
	n.scale = Vector3.ONE * sc
	return n

# 채도 상한을 **텍스처 표면에만** 건다. use_tex는 ToonChar.apply가 원본에 albedo_texture가
# 있을 때만 켜므로 그 자체가 "구운 아틀라스냐" 판정이다 — 단색 표면(마을 팔레트로 지정한
# 색이거나 _glb 경로에서 _repaint가 칠한 색)까지 당기면 팔레트값이 흔들린다.
# gain은 같은 판정(구운 아틀라스냐)에 얹는 밝기 곱 — 식생 킷만 1.0을 넘겨 쓴다(VEG_GAIN 주석).
static func _grade_kit(node: Node, gain := 1.0) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var m := mi.get_surface_override_material(i) as ShaderMaterial
			if m != null and m.get_shader_parameter("use_tex"):
				m.set_shader_parameter("sat_cap", KIT_SAT_CAP)
				m.set_shader_parameter("val_gain", gain)
	for c in node.get_children():
		_grade_kit(c, gain)

func _kit(path: String, sc: float, gain := 1.0) -> Node3D:
	if not _cache.has(path):
		var n := load_kit(path, sc, OUTLINE, gain)
		if n == null:
			return null
		_strip_collision(n)  # 데코 무충돌 계약 (_audit이 런타임에 증명한다)
		_cache[path] = n
	return (_cache[path] as Node3D).duplicate() as Node3D

# MultiMesh용 킷 Mesh: 인스턴스별 surface override가 없으므로 머티리얼을 Mesh에 박는다.
# 캐시를 우회해 매번 새로 로드한다 = 개별 노드(화분·꽃수레 꽃)가 쓰는 Mesh 리소스를 공유
# 변형하지 않는다(Codex MUST-FIX). 겨울 사본도 이 함수로 따로 뽑는다(sat/gain만 다른 별개 Mesh).
# 배율은 인스턴스 transform이 지므로 여기선 항상 native(1.0)로 굽는다.
# tint: 계절 사본이 색을 직접 줄 때만 넘긴다(a=0 = 미지정 → 기존 종별 색조표 경로).
# extra: 셰이더 파라미터를 그대로 얹는다(단풍 사본의 잎 전용 게이트 3종). 빈 사전 = 옛 경로.
func _kit_mesh(nm: String, gain := VEG_GAIN, sat := KIT_SAT_CAP, tint := Color(0, 0, 0, 0),
		extra := {}) -> Mesh:
	var n := load_kit(TT_PARK + kit_of(nm) + ".gltf", 1.0, 0.0, gain)
	if n == null:
		return null
	var mi := _first_mesh(n)
	if mi == null:
		n.free()
		return null
	var mesh := mi.mesh as ArrayMesh
	if mesh == null:
		n.free()
		return null
	for i in mesh.get_surface_count():
		var m := mi.get_surface_override_material(i) as ShaderMaterial
		if m != null:
			m.set_shader_parameter("sat_cap", sat)  # 계절 사본은 여기만 다르다
			for k in extra:
				m.set_shader_parameter(k, extra[k])
			if tint.a > 0.0:  # 단풍·낙엽 사본 = 색을 명시로 준다
				m.set_shader_parameter("char_tint", tint)
			elif FLORA_TINT.has(nm) and sat >= KIT_SAT_CAP:  # 겨울 서리 사본엔 종별 색조를 안 입힌다
				m.set_shader_parameter("char_tint", FLORA_TINT[nm])
			if _atlas == null:
				_atlas = m.get_shader_parameter("albedo_tex")  # 서리 override가 재사용
		mesh.surface_set_material(i, m)
	n.free()  # Mesh는 RefCounted라 여기 참조로 살아 있다
	return mesh

func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return node as MeshInstance3D
	for c in node.get_children():
		var m := _first_mesh(c)
		if m != null:
			return m
	return null

# 킷 원본색 → 마을 팔레트. ToonChar.apply가 깔아둔 toon 머티리얼의 albedo만 바꾼다.
func _repaint(node: Node, swap := {}) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var mat_name := "" if src == null else src.resource_name
			var m := mi.get_surface_override_material(i) as ShaderMaterial
			if m == null:
				continue
			if MAT_COLORS.has(mat_name):
				m.set_shader_parameter("albedo", swap.get(mat_name, MAT_COLORS[mat_name]))
			else:
				_unknown_mats[mat_name] = true
	for c in node.get_children():
		_repaint(c, swap)

# MUST-FIX 1: 데코에 충돌체가 섞이면 통행 계약이 깨진다 — 즉시 free(큐 대기 아님, 감사에서 세지지 않게).
static func _strip_collision(node: Node) -> void:
	for c in node.get_children():
		if c is CollisionObject3D or c is CollisionShape3D:
			node.remove_child(c)
			c.free()
		else:
			_strip_collision(c)

# ══ 금지 존 판정 ════════════════════════════════════════════════════
# 기능 침범 금지 — 소품·꽃·나무 공통. river_keep은 강가 바위처럼 물가에 붙어야 하는 것만 낮춘다.
func _blocked(p: Vector2, river_keep := RIVER_KEEP) -> bool:
	for c in NO_DECOR_CIRCLES:
		if p.distance_to(c[0]) < c[1]:
			return true
	for b in BUILDINGS:
		if absf(p.x - b[0].x) < b[1] and absf(p.y - b[0].y) < b[2]:
			return true
	if FARM.has_point(p) or CAM_LANE.has_point(p) or BEACH_LANE.has_point(p):
		return true
	for r in _roads:
		if _seg_dist(p, r[0], r[1]) < ROAD_KEEP:
			return true
	for br in _bridges:
		if p.distance_to(br) < BRIDGE_KEEP:
			return true
	return _river_dist(p) < river_keep

# 식생 추가 금지 — 판석 위/NPC가 서 있는 자리엔 꽃을 심지 않는다.
func _blocked_flora(p: Vector2) -> bool:
	if _blocked(p) or p.length() < PLAZA_R:
		return true
	for a in NPC_ANCHORS:
		if p.distance_to(a) < ANCHOR_KEEP:
			return true
	for h in NPC_HOMES:
		if p.distance_to(h) < HOME_KEEP:
			return true
	return false

func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0))

func _river_dist(p: Vector2) -> float:
	var best := INF
	for i in _river.size() - 1:
		best = minf(best, _seg_dist(p, _river[i], _river[i + 1]))
	return best

# ══ 절차 지오메트리 (world.gd _box/_cyl와 같은 결) ═════════════════
func _box(parent: Node, center: Vector3, size: Vector3, color: Color, outline := OUTLINE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = ToonChar.solid_or_wood(color, size, outline)
	mi.position = center
	parent.add_child(mi)
	return mi

func _cyl(parent: Node, center: Vector3, radius: float, height: float, color: Color, outline := OUTLINE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.material_override = ToonChar.solid_or_wood_cyl(color, outline)
	mi.position = center
	parent.add_child(mi)
	return mi

# ══ 소품 ═══════════════════════════════════════════════════════════
func _place_props() -> void:
	var root := Node3D.new()
	root.name = "Props"
	add_child(root)
	for p in PROPS:
		var at := Vector2(p[1], p[2])
		if _blocked(at):
			push_warning("decor: 소품 %s (%.1f, %.1f) 금지 존 — 배치 생략" % [p[0], at.x, at.y])
			continue
		var n := Node3D.new()
		n.position = Vector3(at.x, GROUND_Y, at.y)
		n.rotation.y = deg_to_rad(p[3])
		root.add_child(n)
		n.name = p[0]  # 탑다운 도식(decordump)이 종류를 읽는 이름 (Godot이 lamp/lamp2… 로 유일화)
		match p[0]:
			"lamp": _lamp(n)
			"bench": _bench(n)
			"sign": _sign(n)
			"planter": _planter(n)
			"cart": _cart(n)
		_n_props += 1

# 가로등 — Tiny Treats Pretty Park (CC0). 옛 절차 스택(석재 받침 + 목재 기둥 + 크림 유리 박스 +
# 보라 갓지붕 = 프리미티브 4개)을 대체한다. 원본 전고 4.30, 원점 = 지면(밑동 −0.20 스커트는 땅에 잠긴다).
# **전고가 아니라 등 머리 높이를 옛 값에 맞춘다**: 광원 파라미터(LAMP_E·RANGE·ATT)가 등 발치
# 웅덩이를 y3.0 기준으로 실측 튜닝한 값이라, 머리를 옛 자리에서 크게 옮기면 그 튜닝이 통째로 무효다.
# 정점 Y 실측(391정점 히스토그램): 기둥 −0.20~3.00 → 유리 3.05~3.30(반경 0.43) → 갓지붕 3.30~3.99
# → 첨두 4.30. 유리 중심 native 3.17 × 0.90 = 2.85 (옛 3.02에서 −0.17 = 발치 광량 +7%, 무시 가능).
const LAMP_S := 0.90
const LAMP_HEAD_Y := 2.85   # 3.17(native 유리 중심) × LAMP_S — 발광 셸·광원이 공유하는 단일 값
# 킷 등주는 아틀라스가 어두운 금속이라 그대로 심으면 파스텔 마을에서 **화면에서 제일 어두운 물체**가
# 되어 광장 컷의 시선을 통째로 가져간다(실측 after_life_h12: 등 4기가 프레임을 지배). 식생과 같은
# 레버로 마을 대역까지만 올린다(식생 1.85보다 낮은 1.40 = 석재·금속으로는 읽히되 검게 뜨지 않는 선).
const LAMP_GAIN := 1.40
func _lamp(p: Node3D) -> void:
	var n := _kit(TT_PARK + "street_lantern.gltf", LAMP_S, LAMP_GAIN)
	if n != null:
		p.add_child(n)
		_set_layers(n, LAMP_LAYER)  # 아래 light_cull_mask와 짝 — 등불이 제 등갓을 태우지 않게
	# 등갓을 광원에서 뺐으니 유리는 스스로 빛나야 한다: 등 머리를 감싸는 발광 셸
	# (world/window.gdshader = 창불빛과 같은 unshaded + 곡률). 낮엔 glow 0 = 완전 투명이라
	# 킷 등갓이 그대로 보인다 = 낮 룩 무변경.
	# 옛 유리가 정육면체라 박스로 감쌌지만 킷 등갓은 8각기둥(native 반경 0.43 → 0.39)이다 —
	# 박스로 감싸면 네 모서리가 빛나는 쐐기로 삐져나온다. 원통으로 감싼다(0.41 = 0.39 + 여유).
	var g := _cyl(p, Vector3(0, LAMP_HEAD_Y, 0), 0.41, 0.36, C_GLASS, 0.0)
	g.material_override = _glow_mat()
	g.layers = LAMP_LAYER
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var o := OmniLight3D.new()
	o.position = Vector3(0, LAMP_HEAD_Y, 0)
	o.light_color = Color(1.0, 0.86, 0.62)
	o.omni_range = LAMP_RANGE
	o.omni_attenuation = LAMP_ATT
	o.light_cull_mask = ALL_LAYERS & ~LAMP_LAYER
	o.light_energy = 0.0
	p.add_child(o)
	_lights.append(o)

# 킷 노드 트리 전체를 한 렌더 레이어로 (가로등 전용 — 등불 cull_mask에서 통째로 빼기 위함).
func _set_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layers
	for c in node.get_children():
		_set_layers(c, layers)

# 등 유리 발광 머티리얼 1장을 전 가로등이 공유 = 프레임당 파라미터 쓰기 1회.
func _glow_mat() -> ShaderMaterial:
	if _glow == null:
		_glow = ShaderMaterial.new()
		_glow.shader = WINDOW_SHADER
		_glow.set_shader_parameter("tint", C_GLASS)
	return _glow

# 벤치 — Tiny Treats Pretty Park (CC0). 옛 절차 박스 3개(폭 1.70 · 전고 1.18 = 좌판 0.62 +
# 등받이 1.18)를 대체한다. 원본 AABB 2.000×1.406×1.317, 원점 = 바닥 중심.
# 배율 0.85 → 폭 1.70(옛 1.70) · 전고 1.20(옛 1.18) = 옛 프리미티브가 차지하던 크기 그대로.
# 등받이 정점(y>1.0)의 z가 −0.717..−0.176 = **로컬 −z가 등받이**(실측) → 옛 방향 규약과 같아
# PROPS의 yaw를 한 값도 안 고친다. 데코라 충돌체 없음 = WORLD_VERSION 불변.
const BENCH_S := 0.85
func _bench(p: Node3D) -> void:
	var n := _kit(TT_PARK + "bench.gltf", BENCH_S)
	if n != null:
		p.add_child(n)

# 게시판 — Plumberry Plains Props Vol.1 (구매, assets/vendor = 재배포 금지라 gitignore).
# 옛 Kenney sign(0.300×0.409×0.070 ×3.6 = 폭 1.08 · 전고 1.47)을 대체.
# 원본 1.354×1.600×0.971(미터·원점 바닥 중심) → 배율 0.92면 전고 1.47로 옛 값과 같다.
const SIGN_S := 0.92
func _sign(p: Node3D) -> void:
	var n := _kit(VENDOR + "town-life--notice-board/town-life--notice-board.glb", SIGN_S)
	if n != null:
		p.add_child(n)

# 화분: 목재 통 + 흙 + 꽃 3송이
func _planter(p: Node3D) -> void:
	_box(p, Vector3(0, 0.26, 0), Vector3(0.88, 0.52, 0.88), C_WOOD, 0.004)
	_box(p, Vector3(0, 0.54, 0), Vector3(0.7, 0.06, 0.7), C_WOOD_D, 0.0)
	# 킷 꽃은 줄기 위 한 송이가 아니라 납작하고 넓은 지피 꽃이라(native 0.45폭 × 0.14고) 옛 배율
	# 2.6을 그대로 쓰면 폭 1.17이 되어 0.88 화분을 통째로 덮는다. 폭 기준으로 다시 잡는다:
	# 0.78 → 폭 0.35 · 고 0.11. 3송이가 반경 0.18에서 살짝 겹쳐 화분 하나를 채운 무더기가 된다.
	var kinds := ["flower_A~lavender", "flower_A", "flower_A~pink"]
	for i in 3:
		var f := _flower_node(kinds[i])
		var a := TAU * i / 3.0
		f.position = Vector3(cos(a) * 0.18, 0.56, sin(a) * 0.18)
		f.scale = Vector3.ONE * 0.78
		f.rotation.y = a
		p.add_child(f)
		_blooms.append(f)  # 겨울엔 빈 화분만 남는다

# 꽃수레: 목재 짐칸 + 바퀴 2 + 꽃 무더기 (상점 앞 생활감)
func _cart(p: Node3D) -> void:
	_box(p, Vector3(0, 0.72, 0), Vector3(1.5, 0.44, 0.9), C_WOOD, 0.004)
	_box(p, Vector3(0, 0.5, 0), Vector3(1.2, 0.16, 0.7), C_WOOD_D, 0.004)
	_box(p, Vector3(1.05, 0.55, 0), Vector3(0.7, 0.09, 0.09), C_WOOD_D, 0.0)  # 손잡이
	for s in [-1.0, 1.0]:
		var w := _cyl(p, Vector3(0, 0.38, 0.5 * s), 0.36, 0.1, C_WOOD_D, 0.004)
		w.rotation.x = PI * 0.5
	for i in 5:
		var f := _flower_node(["flower_A~lavender", "flower_B", "flower_A~pink", "flower_A~white", "flower_A"][i])
		f.position = Vector3(-0.5 + i * 0.25, 0.94, (i % 2) * 0.3 - 0.15)
		f.scale = Vector3.ONE * 0.85  # 화분과 같은 이유 — 폭 0.38짜리가 0.25 간격으로 겹쳐 무더기가 된다
		f.rotation.y = i * 1.1
		p.add_child(f)
		_blooms.append(f)  # 겨울엔 빈 수레만 남는다

# ══ 울타리 ═════════════════════════════════════════════════════════
func _place_fences() -> void:
	var root := Node3D.new()
	root.name = "Fences"
	add_child(root)
	for run in FENCES:
		var a: Vector2 = run[0]
		var b: Vector2 = run[1]
		var span := (b - a).length()
		var n := maxi(1, int(round(span / FENCE_S)))
		var dir := (b - a) / float(n)
		for k in n:
			var c: Vector2 = a + dir * (k + 0.5)
			if _blocked(c):
				continue  # 길·다리가 지나가는 자리는 비운다 = 출입구
			var seg := _glb("fence_simple")
			if seg == null:
				return
			seg.position = Vector3(c.x, GROUND_Y, c.y)
			seg.rotation.y = atan2(-dir.y, dir.x)  # 조각 장축 = 로컬 +X
			seg.scale = Vector3.ONE * FENCE_S
			root.add_child(seg)
			_n_props += 1

# ══ 꽃 덤불 식생 (MultiMesh만) ═════════════════════════════════════
# 존: ① 길가 띠 ② 광장 둘레 화단 ③ 강변 양안 ④ 초지 옅은 스프링클(민짜 초록 방지).
func _place_flora() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260731
	# 버킷 = 킷 모델 1종 = MultiMesh 1개 = 드로우콜 1. 옛 4종에서 6종으로 늘렸다(덤불·풀에 큰
	# 변종 추가) — 같은 모델이 반복되는 게 "통짜"로 읽히던 원인의 절반이라, 드로우콜 +2로 산다.
	var buckets := {}
	for nm in FLORA_BUCKETS:
		buckets[nm] = []

	# ① 길가 띠 — 길 중심선에서 2.3~4.2 벗어난 양쪽
	for r in _roads:
		var a: Vector2 = r[0]
		var b: Vector2 = r[1]
		var span := (b - a).length()
		var dir := (b - a) / maxf(span, 0.01)
		var perp := Vector2(-dir.y, dir.x)
		for k in int(span / 2.6):
			for s in [1.0, -1.0]:
				if rng.randf() < 0.28:
					continue
				var c: Vector2 = a + dir * ((k + rng.randf()) * 2.6) + perp * (s * rng.randf_range(2.3, 4.2))
				# 라벤더를 두 번 넣어 가중치를 준다 — 목록은 균등 추첨이라 이게 유일한 비중 조절
				# 수단이다(MultiMesh는 인스턴스별 색이 없어 버킷을 가르는 것 말고는 방법이 없다).
				_add_flora(buckets, c, rng, ["flower_A~lavender", "flower_A~lavender", "flower_A",
					"flower_A~white", "flower_B", "flower_A~pink", "bush", "grass_A"])

	# ② 광장 둘레 화단 — 판석 바깥 링(방사길 사이 구간만 남는다)
	for _i in 220:
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(6.6, 9.6)
		_add_flora(buckets, Vector2(cos(ang), sin(ang)) * rad, rng,
			["flower_A~lavender", "flower_A~lavender", "flower_A", "flower_A~pink",
			"flower_B", "flower_A~white"])

	# ③ 강변 양안 — 물폭3 + 강둑 바깥
	for i in _river.size() - 1:
		var a: Vector2 = _river[i]
		var b: Vector2 = _river[i + 1]
		var span := (b - a).length()
		var dir := (b - a) / maxf(span, 0.01)
		var perp := Vector2(-dir.y, dir.x)
		for k in int(span / 3.0):
			for s in [1.0, -1.0]:
				if rng.randf() < 0.30:
					continue
				var c: Vector2 = a + dir * ((k + rng.randf()) * 3.0) + perp * (s * rng.randf_range(3.2, 5.2))
				_add_flora(buckets, c, rng, ["flower_A~lavender", "flower_B", "flower_A~white",
					"flower_A", "grass_B", "bush_large"])

	# ④ 초지 스프링클 — 풀포기·덤불 + 라벤더. 옛 판은 꽃을 길·광장·강변 세 존에만 뒀는데,
	# 그러면 **꽃이 전부 사람이 다니는 선 위에만** 있어 들판은 단색 초지로 남는다. 마을 정체가
	# "라벤더가 가득한 마을"이면 라벤더는 화단이 아니라 들에 있어야 한다. 다섯 중 하나 = ~20%.
	for _i in 190:
		var c := Vector2(rng.randf_range(-WALK_HALF, WALK_HALF), rng.randf_range(-WALK_HALF, WALK_HALF))
		_add_flora(buckets, c, rng, ["grass_A", "grass_B", "flower_A~lavender", "grass_A", "bush_large"])

	_lavender_rows(buckets)

	for nm in buckets:
		if (buckets[nm] as Array).is_empty():
			continue
		_multimesh(_flora_mesh(nm), buckets[nm], "Flora_" + nm)
		_n_flora += (buckets[nm] as Array).size()

# ══ 라벤더 이랑 ═══════════════════════════════════════════════════
# 흩뿌린 꽃 수백 송이보다 **이랑 몇 줄**이 "라벤더 마을"이라고 훨씬 크게 말한다 — 줄로 서 있다는
# 건 사람이 심었다는 뜻이고, 그게 마을의 생업이 된다. 자리는 풍차 언덕 진입로(북동 다리 → 램프)의
# 동안 평지: 다리를 건너 풍차로 올라가는 동선이 통째로 이랑 사이를 지난다 = 플레이어가 반드시 본다.
# 버킷은 기존 라벤더 것을 그대로 쓴다 = 드로우콜 추가 없음.
# 밭 서쪽 끝은 강에 물린다 — 일부러 그렇게 잡았다. _blocked_flora가 물·둑에서 잘라 주므로
# 밭이 강가에서 끝나는 자연스러운 경계가 공짜로 나온다(직선으로 끊으면 잔디밭에 붙인 스티커).
const LAV_CENTER := Vector2(28.0, -10.0)
const LAV_YAW := 0.30      # 이랑 방향(라디안) — 강 흐름과 나란하게
const LAV_ROWS := 10
const LAV_ROW_GAP := 1.45  # 이랑 간격(사이로 걸어 다닐 수 있는 폭)
const LAV_STEP := 0.55     # 이랑 안 포기 간격
const LAV_LEN := 10.0

# rng를 따로 쓴다 — 공용 스트림에 끼어들면 이 뒤에 뽑히는 나무·소품 자리가 통째로 밀린다.
func _lavender_rows(buckets: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260814
	var dir := Vector2(sin(LAV_YAW), cos(LAV_YAW))
	var perp := Vector2(dir.y, -dir.x)
	var arr: Array = buckets["flower_A~lavender"]
	var sc: Vector2 = FLORA_SCALE["flower_A"]
	var n := int(LAV_LEN / LAV_STEP)
	for r in LAV_ROWS:
		var off := (r - (LAV_ROWS - 1) * 0.5) * LAV_ROW_GAP
		for k in n:
			var along := (k - (n - 1) * 0.5) * LAV_STEP
			# 줄은 곧되 포기는 흔들린다. 완전 정렬은 손으로 심은 밭이 아니라 기계 출력으로 읽힌다.
			var p := LAV_CENTER + dir * (along + rng.randf_range(-0.10, 0.10)) \
				+ perp * (off + rng.randf_range(-0.13, 0.13))
			if _blocked_flora(p):
				continue  # 길·물·소품 자리에서 끊긴다 = 밭을 가로지르는 길로 읽힌다
			var t := Transform3D()
			t = t.scaled(Vector3.ONE * rng.randf_range(sc.x, sc.y))
			t = t.rotated(Vector3.UP, rng.randf() * TAU)
			t.origin = Vector3(p.x, GROUND_Y, p.y)
			arr.append(t)

# ══ 가을 낙엽 산포 ═══════════════════════════════════════════════════
# 가을은 꽃이 노랑 하나만 남아 화단 밀도가 빈다 — 그 자리를 바닥에 깔린 낙엽이 메운다.
# 메시는 flower_A를 그대로 쓴다: 킷의 **납작하고 넓은 지피 꽃**(native 0.45폭 × 0.138고)이라
# 눕히면 그대로 바닥 잎이다 = 새 에셋 0, 드로우콜 +1(꽃 변종 하나와 같은 비용).
# 채도를 지우고 낙엽색을 입히는 처방(단풍 사본과 같은 순서)이라 꽃심·꽃잎 구분이 사라져
# "바닥에 떨어진 잎"으로 읽힌다 — 채도를 남기면 갈색 꽃이 핀 것으로 보인다.
const LEAF_MM := "LeafLitter"
const LEAF_CLUSTERS := 240
# 수관 단풍(TREE_AUTUMN_TINT 0.831,0.552,0.326)보다 한 단 어둡고 붉다 — 바닥 잎은 이미 마른
# 것이고, 수관과 같은 값을 쓰면 지면 위 잎이 나무 그늘에서 되레 더 밝게 떠 붕 뜬다.
# 결과 albedo 최대채널 ≈ 0.60 = 가을 초지(0.610,0.640,0.412) 위에서 R>G로 갈린다.
const LEAF_TINT := Color(0.700, 0.438, 0.262)
const LEAF_SAT := 0.14
const LEAF_GAIN := 1.55

# 바닥 낙엽 사본 한 벌 — 채도를 지우고(sat) 낙엽색을 tint로 주는 순서는 단풍 사본과 같다.
# **_place_leaf_litter와 test_core가 같이 부르는 유일한 통로다.** 인자를 테스트에 복사해 두면
# 여기 처방이 되돌아가도 핀이 안 문다(tree_slots와 같은 이유 — 02b11cd·99e89ac에서 두 번 겪었다).
func leaf_litter_mesh() -> Mesh:
	return _kit_mesh("flower_A", LEAF_GAIN, LEAF_SAT, LEAF_TINT)

# rng는 **전용 고정 시드**다. 공용 스트림에 끼어들면 그 뒤에 뽑히는 나무·강변 바위·소품 자리가
# 통째로 밀린다(_lavender_rows·_place_forest 원경 띠가 같은 이유로 전용 시드를 쓴다 — 실증).
func _place_leaf_litter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260825
	var xf := []
	for _i in LEAF_CLUSTERS:
		var at := Vector2(rng.randf_range(-WALK_HALF, WALK_HALF), rng.randf_range(-WALK_HALF, WALK_HALF))
		for _k in rng.randi_range(3, 6):  # 뭉쳐 깔린다(_add_flora와 같은 이유 — 낱개는 잡티로 읽힌다)
			var p := at + Vector2(rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2))
			if _blocked_flora(p):
				continue  # 길·물·판석·NPC 자리 제외 = 낙엽이 강물 위에 뜨지 않는다
			var s := rng.randf_range(1.15, 1.75)
			var t := Transform3D()
			t = t.scaled(Vector3(s, s * 0.45, s))  # 높이만 깎아 눕힌다(폭은 그대로 = 바닥에 깔린 잎)
			t = t.rotated(Vector3.UP, rng.randf() * TAU)
			t.origin = Vector3(p.x, GROUND_Y, p.y)
			xf.append(t)
	_multimesh(leaf_litter_mesh(), xf, LEAF_MM)

# 한 자리에 3~6포기를 뭉쳐 심는다 — 낱개로 흩뿌리면 "잡초 노이즈"로 보이고 화단으로 안 읽힌다.
func _add_flora(buckets: Dictionary, at: Vector2, rng: RandomNumberGenerator, kinds: Array) -> void:
	if _blocked_flora(at):
		return
	for _i in rng.randi_range(3, 6):
		var p := at + Vector2(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.9, 0.9))
		if _blocked_flora(p):
			continue
		var nm: String = kinds[rng.randi() % kinds.size()]
		var sc: Vector2 = FLORA_SCALE[kit_of(nm)]
		var t := Transform3D()
		t = t.scaled(Vector3.ONE * rng.randf_range(sc.x, sc.y))
		t = t.rotated(Vector3.UP, rng.randf() * TAU)
		t.origin = Vector3(p.x, GROUND_Y, p.y)
		(buckets[nm] as Array).append(t)

# ══ 계절 식생 (계절 파생 — 저장 없음, transform 재빌드 없음) ═══════
# 꽃은 **계절 시계**다(아래 FLOWER_SEASONS). 겨울엔 한 종도 안 핀다: 눈 지면 위에 만개한 꽃이
# 계절 감각을 통째로 깬다.
# 풀·덤불은 겨울에 숨기는 대신 서리톤으로 남긴다 — 통째로 지우면 마을이 민짜 눈판이 되고
# 길가 띠·광장 화단 링·강변의 밀도와 실루엣이 같이 사라진다(꽃만 빼도 계절은 읽힌다).
# 나무는 킷 교체로 전부 활엽이 됐다(Tiny Treats 파크 킷에 침엽수가 없다) → 겨울엔 전 그루가
# 서리톤, 가을엔 전 그루가 단풍이다. 옛 규약("침엽수는 계절 밖에서 초록으로 실루엣을 진다")은
# 이제 해변 해송만 진다 — 가을에 혼자 초록으로 남아 단풍과 대비를 만들어 주므로 의도된 동작이다.
const SPRING := 0
const SUMMER := 1
const AUTUMN := 2
const WINTER := 3
# 꽃은 변종이 늘어나므로 "꽃이냐"의 판정은 목록이 아니라 **접두 규칙**이다 — 목록이면 새 색을
# 추가할 때마다 여기 적는 걸 잊고 겨울 설원에 분홍 꽃이 만개한 채 남는다.
const FLORA_FLOWER_PREFIX := "Flora_flower"
const DECIDUOUS := ["Forest_tree", "Forest_tree_large"]
# 꽃 색 변종별로 피는 계절. **새 버킷을 만들지 않는다** — 변종 하나당 드로우콜 +1이라 계절마다
# 새 색을 파면 비용이 곱으로 는다. 기존 버킷의 가시성만 계절로 여닫는다.
# 배분의 핵심은 **여름 = 라벤더 절정**이다: 라벤더 이랑(_lavender_rows)이 만개하는 계절이 있어야
# "라벤더로 먹고사는 마을"이라는 서사가 화면에서 성립한다.
# 흰 데이지는 봄·여름 양쪽에 둔다 — 어느 계절이든 흰색이 한 겹 섞여야 화단이 단색으로 안 읽힌다.
# 푸른 flower_B는 여름에만 둔다: **미지정으로 두면 조용히 사라지므로 명시가 곧 계약이다**.
# 연못·하늘과 같은 시원한 계열이라 여름 그림에 맞는다.
# 가을은 노랑 한 색뿐이라 화단 밀도가 빈다 — 그 자리는 바닥 낙엽(_place_leaf_litter)이 메운다.
const FLOWER_SEASONS := {
	"flower_A": [AUTUMN],                     # 노랑(개나리 계승) — 가을 화단을 혼자 진다
	"flower_A~white": [SPRING, SUMMER],
	"flower_A~pink": [SPRING],
	"flower_A~lavender": [SUMMER],            # 마을 정체색 — 여름 만개
	"flower_B": [SUMMER],
}

# MultiMesh 이름("Flora_flower_A~pink") → 버킷 이름("flower_A~pink"). 접두 처리 **단일 출처**다 —
# 호출부마다 trim_prefix를 쓰면 한 곳만 빠져도 표가 조용히 안 걸린다(kit_of와 같은 규약).
static func bucket_of(nm: String) -> String:
	return nm.trim_prefix("Flora_")

static func flora_visible(nm: String, season: int) -> bool:
	if not nm.begins_with(FLORA_FLOWER_PREFIX):
		return true  # 풀·덤불은 사계절 상주(겨울엔 서리톤으로 남는다)
	return season in FLOWER_SEASONS.get(bucket_of(nm), [])

static func flora_frosted(nm: String, season: int) -> bool:
	return season == WINTER and nm.begins_with("Flora_") and flora_visible(nm, season)

# 가을 지피 톤은 **풀·덤불만**이다. 꽃(flower_A 노랑)에 걸면 FLORA_TINT가 덮여 가을 화단이
# 통째로 사라진다 — 배제는 flora_visible과 같은 접두 규칙을 쓴다(목록이면 새 변종에서 샌다).
static func flora_autumn(nm: String, season: int) -> bool:
	return season == AUTUMN and nm.begins_with("Flora_") and not nm.begins_with(FLORA_FLOWER_PREFIX)

# 활엽수 메시 슬롯 [원색, 겨울 서리, 가을 단풍] 중 하나. 인라인 삼항을 중첩하지 않고 순수 함수로
# 두는 이유: 슬롯이 늘 때마다 apply_season 안의 인덱스 식이 조용히 깨진다(옛 판은 2슬롯 계약인
# `[1 if ... else 0]`이었다) — 여기 있으면 노드 없이 테스트가 잡는다.
static func tree_variant_index(nm: String, season: int) -> int:
	if not nm in DECIDUOUS:
		return 0  # 침엽수(해변 해송)는 사계절 원색
	match season:
		WINTER: return 1
		AUTUMN: return 2
		_: return 0

static func tree_frosted(nm: String, season: int) -> bool:
	return tree_variant_index(nm, season) == 1

# 활엽수 한 종의 계절 사본 한 벌 — 슬롯 순서는 위 tree_variant_index의 계약 [원색, 겨울, 가을]이다.
# 겨울·가을 사본은 빌드 때 미리 뽑는다(전환 때 로드하지 않게). 텍스처는 그대로 두고 채도만 지우고
# 밝기를 올린 별개 Mesh — 옛 방식(수관 albedo를 단색으로 교체)은 킷 나무에선 잎 결까지 통째로
# 뭉개져 그 계절에만 다시 통짜가 된다. 봄·여름은 원색을 공유한다 = 종당 사본 2개(나무 2종에 Mesh 4장).
# **_place_forest와 test_core가 같이 부르는 유일한 통로다.** 인자를 테스트에 복사해 두면 여기 처방이
# 옛 판으로 되돌아가도 핀이 안 문다(02b11cd에서 같은 구멍을 한 번 겪었다).
func tree_slots(nm: String) -> Array:
	return [_kit_mesh(nm),
		_kit_mesh(nm, TREE_WINTER_GAIN, VEG_WINTER_SAT),
		_kit_mesh(nm, TREE_AUTUMN_GAIN, KIT_SAT_CAP, Color(0, 0, 0, 0), TREE_AUTUMN_EXTRA)]

# 만개한 꽃(화분·꽃수레의 개별 꽃 GLB, 등나무 드레이프)은 겨울에만 숨긴다. 서리톤으로 남기지 않는
# 이유: 회색으로 물든 만개 송이는 눈 위에 매달린 이물처럼 보인다 — 빈 화분·빈 수레·맨 퍼걸러가
# 겨울 그림으로 맞다.
# **들꽃(FLOWER_SEASONS)과 달리 계절로 안 나눈다**: 화분·꽃수레는 사람이 관리하는 물건이라
# 계절 따라 송이가 사라지면 오히려 어색하고, 들꽃이 비는 가을에 마을 안 색을 붙잡아 주는 게
# 이쪽이다. 겨울만 갈리는 이 계약은 test_core가 사계절 전부 못박는다.
static func bloom_visible(season: int) -> bool:
	return season != WINTER

# 바닥 낙엽(_place_leaf_litter)은 가을에만 깔린다.
static func leaf_litter_visible(season: int) -> bool:
	return season == AUTUMN

# world.gd _apply_season이 계절 전환 신호 + 로드 직후에 부른다(축제 evaluate와 같은 규약).
func apply_season(sea: int) -> void:
	for c in get_children():
		var mmi := c as MultiMeshInstance3D
		if mmi == null:
			continue
		var nm := String(mmi.name)
		if _tree_mesh.has(nm):  # 활엽수: transform 버퍼는 그대로 두고 Mesh만 갈아 끼운다
			mmi.multimesh.mesh = _tree_mesh[nm][tree_variant_index(nm, sea)]
			continue
		if nm == LEAF_MM:
			mmi.visible = leaf_litter_visible(sea)
			continue
		if not nm.begins_with("Flora_"):
			continue
		mmi.visible = flora_visible(nm, sea)
		# 색은 MultiMeshInstance3D의 material_override로만 바꾼다. MultiMesh의 Mesh 표면
		# 머티리얼을 고쳐 쓰면 같은 킷을 쓰는 개별 소품(화분 꽃·꽃수레)과 리소스를 공유할
		# 위험 + 원색 복구용 백업 보관까지 딸려온다. override는 null로 지우면 원색이 돌아온다.
		mmi.material_override = null
		if flora_frosted(nm, sea):
			mmi.material_override = _frost_mat()
		elif flora_autumn(nm, sea):
			mmi.material_override = _autumn_mat()
	for b in _blooms:
		b.visible = bloom_visible(sea)

# 겨울 식생 서리 머티리얼 1장을 전 식생 버킷이 공유한다 — 파크 킷은 종이 달라도 **같은 아틀라스**를
# 쓰므로 override 한 장으로 전부 덮인다. 옛 단색(make_solid(C_FROST))을 쓰면 겨울에만 다시
# 통짜가 되므로 텍스처는 살리고 채도만 지운 뒤 밝기를 올린다 = 잎 결이 남은 "서리 앉은 풀".
func _frost_mat() -> ShaderMaterial:
	if _frost == null:
		_frost = _veg_mat(FLORA_WINTER_TINT, VEG_WINTER_SAT, FLORA_WINTER_GAIN, C_FROST)
	return _frost

# 가을 지피도 같은 한 장을 공유한다(같은 아틀라스). 꽃은 flora_autumn이 접두로 뺀다.
func _autumn_mat() -> ShaderMaterial:
	if _autumn == null:
		_autumn = _veg_mat(FLORA_AUTUMN_TINT, FLORA_AUTUMN_SAT, FLORA_AUTUMN_GAIN, FLORA_AUTUMN_TINT)
	return _autumn

func _veg_mat(tint: Color, sat: float, gain: float, fallback: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ToonChar.TOON
	m.set_shader_parameter("char_tint", tint)
	m.set_shader_parameter("sat_cap", sat)
	m.set_shader_parameter("val_gain", gain)
	if _atlas != null:
		m.set_shader_parameter("use_tex", true)
		m.set_shader_parameter("albedo_tex", _atlas)
	else:
		m.set_shader_parameter("albedo", fallback)  # 에셋 누락 폴백
	return m

# ══ 절차 블롭 나무 (해변 해송 전용으로 축소) ══════════════════════════
# 마을 나무 218그루는 킷 모델로 전면 교체했다(_place_forest). 여기 남은 건 **해변 해송 한 종뿐**이다
# — 파크 킷에 침엽수가 없어서 beach.gd가 계속 이 문법을 쓴다. 마을에서 안 쓰는 활엽 블롭 2종과
# cone_tall은 지웠다(죽은 코드).
# 파라미터 [수관 반경, 수관 y중심, y스쿼시, 상단 테이퍼(1=구/0.25=침엽), 줄기 반경, 줄기 높이, 로브 세기]
const BLOB_KINDS := {
	"cone_slim":  [0.32, 0.66, 1.70, 0.24, 0.066, 0.24, 0.13],  # 가는 침엽 — beach.gd 해송
}
const CONIFER := ["cone_slim"]
# 로브 방향 — 수관을 몇 방향으로만 부풀려 완벽한 구가 아닌 뭉게구름 실루엣을 만든다.
const LOBES := [Vector3(1, 0.3, 0.4), Vector3(-0.8, 0.15, 0.6), Vector3(0.25, 0.55, -1), Vector3(-0.45, -0.15, -0.85)]

# static = 노드 없이도 만들 수 있다(beach.gd 해송이 같은 실루엣을 쓴다 — 나무 문법 단일 출처).
static func blob_mesh(k: Array, leaf: Color, seg := 22, rings := 12) -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = seg
	sm.rings = rings
	var a := sm.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	for i in v.size():
		var n := v[i].normalized()
		var bulge := 1.0
		for d in LOBES:
			bulge += float(k[6]) * pow(maxf(n.dot((d as Vector3).normalized()), 0.0), 2.0)
		var t := (n.y + 1.0) * 0.5                    # 0=아래 1=위
		var taper: float = lerpf(1.0, float(k[3]), t * t)  # 위로 갈수록 좁아진다
		v[i] = Vector3(n.x * taper, n.y * float(k[2]), n.z * taper) * (bulge * float(k[0]))
		v[i].y += float(k[1])
	var tmp := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_INDEX] = a[Mesh.ARRAY_INDEX]
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# 정점을 옮겼으니 법선을 다시 만든다 — 인덱스 메시라 스무스 셰이딩(각진 면이 안 남는다).
	var st := SurfaceTool.new()
	st.create_from(tmp, 0)
	st.generate_normals()
	var out := st.commit() as ArrayMesh
	# 통통한 줄기(아래가 넓은 원통). 수관 밑동에 파묻히게 배치.
	var cm := CylinderMesh.new()
	cm.top_radius = float(k[4]) * 0.8
	cm.bottom_radius = float(k[4]) * 1.35
	cm.height = float(k[5])
	cm.radial_segments = 12
	cm.rings = 1
	var ca := cm.surface_get_arrays(0)
	var cv: PackedVector3Array = ca[Mesh.ARRAY_VERTEX]
	for i in cv.size():
		cv[i].y += float(k[5]) * 0.5
	ca[Mesh.ARRAY_VERTEX] = cv
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ca)
	out.surface_set_material(0, ToonChar.make_solid(leaf, OUTLINE))
	out.surface_set_material(1, ToonChar.make_solid(C_WOOD, OUTLINE))
	return out

# 식생 버킷 이름 → Mesh (= 킷 파일명). 종당 1장을 캐시해 MultiMesh와 화분·꽃수레의 개별 꽃이
# **같은 리소스**를 쓴다 — 구운 뒤 아무도 안 고치므로(겨울 서리는 MultiMeshInstance3D의
# material_override로만 걸린다) 공유가 안전하다.
func _flora_mesh(nm: String) -> Mesh:
	if not _flora_cache.has(nm):
		_flora_cache[nm] = _kit_mesh(nm)
	return _flora_cache[nm]

# 화분·꽃수레의 개별 꽃 한 송이(만개 — 겨울엔 _blooms로 숨긴다).
func _flower_node(kind: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _flora_mesh(kind)
	return mi

# ══ 숲 띠 (경계 |x| 또는 |z| ∈ [34,40] 저밀도, 킷 나무 MultiMesh) ══
# 나무 = Tiny Treats Pretty Park 킷 2종(CC0). 옛 절차 블롭 4종을 전부 대체한다.
# 배율 근거 — **옛 전고 대역을 계승**한다(배치 밀도·keepout이 그 크기 전제로 승인돼 있다).
#   옛 마을 띠: 블롭 전고 0.96~1.34 × 배율 2.7~4.0 = 2.6~5.3m
#   옛 원경 띠: 같은 블롭 × 4.0~6.0 = 3.8~8.0m
#   킷 native 전고: tree 3.42 / tree_large 4.78 (원점 = 지면, 밑동 −0.20 스커트는 땅에 잠긴다)
const TREE_KIT := {  # 킷 파일명 → [마을 띠 배율, 원경 띠 배율]
	"tree":       [Vector2(0.80, 1.15), Vector2(1.25, 1.80)],  # 2.7~3.9m / 4.3~6.2m
	"tree_large": [Vector2(0.70, 0.95), Vector2(1.05, 1.50)],  # 3.3~4.5m / 5.0~7.2m
}

func _place_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260724  # 컬러박스와 같은 시드 = 띠 실루엣 연속성
	var kinds := TREE_KIT.keys()
	var buckets := {}
	for k in kinds:
		buckets[k] = []
	for edge in 4:  # 0=북(-z) 1=남(+z) 2=서(-x) 3=동(+x)
		for _i in 26:  # 띠 한 변당 — 이보다 낮으면 곡률에 가려 '숲 띠'로 안 읽힌다(실측)
			var along := rng.randf_range(-39.0, 39.0)
			var band := rng.randf_range(33.5, 39.5)
			var pos: Vector2
			match edge:
				0: pos = Vector2(along, -band)
				1: pos = Vector2(along, band)
				2: pos = Vector2(-band, along)
				_: pos = Vector2(band, along)
			if _blocked(pos):
				continue
			# rng 소비 개수·순서를 옛 코드와 글자 그대로 맞춘다(along·band·randi·scale·rot = 5,
			# 금지 존이면 2) — 이 스트림은 아래 강변 바위와 공유라 소비가 어긋나면 바위가 통째로 밀린다.
			var nm: String = kinds[rng.randi() % kinds.size()]
			var sc: Vector2 = TREE_KIT[nm][0]
			var t := Transform3D()
			t = t.scaled(Vector3.ONE * rng.randf_range(sc.x, sc.y))
			t = t.rotated(Vector3.UP, rng.randf() * TAU)
			t.origin = Vector3(pos.x, GROUND_Y, pos.y)
			(buckets[nm] as Array).append(t)
	# 원경 띠 — 지평선 너머 숲. 옛 그림은 지평선이 잔디와 하늘의 **직선 경계**였다(실측
	# audit2_0809/bridge_sw_h12). 툰 곡률(0.006·z²)이 시야 32.6 지점을 정점으로 지면을 도로
	# 내리므로, 이 대역(44~56)의 밑동은 지평선 아래로 잠기고 **수관만** 띠로 떠오른다 = 원경 실루엣.
	# 그래서 나무를 크게(4.0~6.0) 잡아야 한다 — 안쪽 띠 배율로는 통째로 잠긴다.
	# 같은 버킷에 넣으므로 **드로우콜 증가 0**이고, MultiMesh는 노드 단위 컬링이라
	# 곡률 변위-AABB 불일치(816286e 풍차 지붕)에도 걸리지 않는다.
	# rng를 따로 쓴다 — 위 rng는 아래 강변 바위와 스트림을 공유하므로, 여기서 난수를 뽑으면
	# 바위 자리가 통째로 밀린다(실측: 승인된 바위 2개가 금지 존으로 밀려 사라졌다).
	var frng := RandomNumberGenerator.new()
	frng.seed = 20260809
	for edge in 4:
		for _i in 30:
			var along := frng.randf_range(-56.0, 56.0)
			var band := frng.randf_range(44.0, 56.0)
			var pos: Vector2
			match edge:
				0: pos = Vector2(along, -band)
				1: pos = Vector2(along, band)
				2: pos = Vector2(-band, along)
				_: pos = Vector2(band, along)
			if _blocked(pos):
				continue
			var nm: String = kinds[frng.randi() % kinds.size()]
			var sc: Vector2 = TREE_KIT[nm][1]
			var t := Transform3D()
			t = t.scaled(Vector3.ONE * frng.randf_range(sc.x, sc.y))
			t = t.rotated(Vector3.UP, frng.randf() * TAU)
			t.origin = Vector3(pos.x, GROUND_Y, pos.y)
			(buckets[nm] as Array).append(t)
	for nm in buckets:
		if (buckets[nm] as Array).is_empty():
			continue
		var full: String = "Forest_" + nm
		var slots := tree_slots(nm)
		_multimesh(slots[tree_variant_index(full, SUMMER)], buckets[nm], full)
		_n_trees += (buckets[nm] as Array).size()
		if tree_frosted(full, WINTER):
			_tree_mesh[full] = slots

	# 강변 바위 몇 개 — 물길이 지형에 박혀 보이게(개별 노드, 무충돌)
	var rocks := Node3D.new()
	rocks.name = "Rocks"
	add_child(rocks)
	for i in _river.size() - 1:
		for s in [1.0, -1.0]:
			var a: Vector2 = _river[i]
			var b: Vector2 = _river[i + 1]
			var dir := (b - a).normalized()
			var c: Vector2 = a + (b - a) * rng.randf_range(0.25, 0.75) + Vector2(-dir.y, dir.x) * (s * rng.randf_range(2.6, 3.4))
			if _blocked(c, 2.4):
				continue  # 강가엔 붙이되(river_keep 2.4) 물 위·다른 금지 존은 제외
			var r := _glb("rock_smallA" if (i + int(s)) % 2 == 0 else "rock_smallB")
			if r == null:
				continue
			r.position = Vector3(c.x, GROUND_Y, c.y)
			r.scale = Vector3.ONE * rng.randf_range(2.2, 3.8)
			r.rotation.y = rng.randf() * TAU
			rocks.add_child(r)
			_n_props += 1

# ══ 등나무(보라) 처마 — 퍼걸러·회관 파사드·다리 난간 (VILLAGE_SPEC §3) ══
func _wisteria() -> void:
	var root := Node3D.new()
	root.name = "Wisteria"
	add_child(root)
	_blooms.append(root)  # 등나무는 낙엽성 — 겨울엔 퍼걸러·난간 골조만 남는다
	# 정자 퍼걸러(-26,14): 지붕 4.2각(y2.7~3.05) 가장자리에서 늘어뜨린다
	for i in 14:
		var t := i / 14.0 * TAU
		var e := Vector2(cos(t), sin(t))
		var m := maxf(absf(e.x), absf(e.y))
		var p := Vector2(-26, 14) + e / m * 2.0
		_drape(root, Vector3(p.x, 2.55, p.y), 0.5 + fmod(i * 0.37, 0.5))
	# 회관 파사드(0,-18): 남면 처마 아래(z=-15.6). 박스 회관 전용 — 모델 회관은 처마가 다른
	# 자리라 world.gd가 끈다(안 끄면 등나무만 공중에 남는다).
	if hall_drapes:
		for i in 7:
			_drape(root, Vector3(-2.55 + i * 0.85, 4.62, -15.30), 0.7 + fmod(i * 0.41, 0.8))
	# 다리 난간 포인트 — 데크는 강을 가로지르므로 흐름 수직(perp)이 난간 장축이다(world.gd _arch_bridge와 동일식)
	for br in _bridges:
		var ang := _river_dir_at(br)
		var flow := Vector2(sin(ang), cos(ang))
		var perp := Vector2(cos(ang), -sin(ang))
		for fs in [-1.0, 1.0]:
			for ps in [-1.0, 1.0]:
				# 흐름 방향 1.78 = 난간 바깥. 옛 1.5는 난간 중심선(world.gd 데크 z=±1.5)이라
				# _drape이 아래로 늘어뜨리는 송이가 난간·갓돌 속에 파묻히고 끝만 석재를 뚫고 나왔다
				# (실측 arch_h12: 보라 포인트가 다리를 관통해 떠 있음).
				# 1.78 = 갓돌 바깥면 1.63(z 1.5 + 갓돌 반지름 0.13) + 송이 반폭 0.11 + 여유 0.04.
				var q: Vector2 = br + flow * (1.78 * fs) + perp * (2.2 * ps)
				# 1.10 = 풀 아치 데크 갓돌 상단 = world.gd deck_top(2.2) + 0.40
				#      = (DECK_CROWN 1.30 − (DECK_ARC_R 4.35 − √(4.35² − 2.2²))) + 0.40 = 0.703 + 0.40.
				# world.gd가 decor.gd를 preload하므로 역방향 preload는 순환 — 파생식을 주석으로
				# 남기고 상수로 박는다. 어긋나면 test_core의 deck_top 핀이 잡는다.
				_drape(root, Vector3(q.x, 1.10, q.y), 0.45)

# 점 p에서 가장 가까운 강 세그먼트의 흐름 방향(y회전각) — world.gd _river_dir_at와 같은 식.
func _river_dir_at(p: Vector2) -> float:
	var best := 0.0
	var best_d := INF
	for i in _river.size() - 1:
		var d := _seg_dist(p, _river[i], _river[i + 1])
		if d < best_d:
			best_d = d
			best = atan2(_river[i + 1].x - _river[i].x, _river[i + 1].y - _river[i].y)
	return best

# 등나무 송이: 아래로 가늘어지는 보라 2단 (간단 메시 — 발주서 허용)
func _drape(parent: Node, at: Vector3, drop: float) -> void:
	_box(parent, at + Vector3(0, -drop * 0.3, 0), Vector3(0.22, drop * 0.6, 0.22), C_WIST, 0.004)
	_box(parent, at + Vector3(0, -drop * 0.78, 0), Vector3(0.13, drop * 0.42, 0.13), C_LILAC, 0.004)

# ══ 공통 ═══════════════════════════════════════════════════════════
func _multimesh(mesh: Mesh, xforms: Array, nm: String) -> void:
	if mesh == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	if _dumping:
		var pts := PackedVector2Array()
		for t in xforms:
			pts.append(Vector2((t as Transform3D).origin.x, (t as Transform3D).origin.z))
		_mm_pts[nm] = pts
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	# 곡률(toon.gdshader v.y -= 0.006·z²)은 정점을 **셰이더에서** 내리므로 AABB가 그 변위를 모른다.
	# 키 큰 물체가 프레임 상단에 걸리면 통째로 컬링될 수 있다(816286e 풍차 지붕 전례).
	# MultiMesh는 노드 하나가 띠 전체를 덮어 실질적으로 컬링 대상이 아니지만, 여유는 공짜다.
	mmi.extra_cull_margin = 8.0
	add_child(mmi)

# MUST-FIX 1: 데코 루트 아래 충돌체가 하나도 없음을 런타임 로그로 증명한다.
func _audit() -> void:
	var bodies := _count_collision(self)
	print("decor: props=%d flora=%d trees=%d lights=%d collision_bodies=%d"
		% [_n_props, _n_flora, _n_trees, _lights.size(), bodies])
	print("decor perf: " + _perf())
	if bodies > 0:
		push_error("decor: 충돌체 %d개가 데코 트리에 남았다 — 통행 계약 위반" % bodies)
	if not _unknown_mats.is_empty():
		print("decor: 팔레트 미지정 머티리얼 ", _unknown_mats.keys())
	if _dumping:  # 탑다운 도식 대조용 좌표 덤프(검증 전용)
		_dump()

# 배치 좌표를 한 줄 JSON으로 뱉는다 — PIL 도식 스크립트가 stdout에서 파싱한다.
func _dump() -> void:
	var out := {"props": [], "mm": {}}
	for group in ["Props", "Fences", "Rocks"]:
		var g := get_node_or_null(group)
		if g == null:
			continue
		for c in g.get_children():
			var kind: String = String(c.name).rstrip("0123456789") if group == "Props" else String(group).to_lower()
			out["props"].append([snappedf((c as Node3D).position.x, 0.01), snappedf((c as Node3D).position.z, 0.01), kind])
	for nm in _mm_pts:
		var pts := []
		for v in (_mm_pts[nm] as PackedVector2Array):
			pts.append([snappedf(v.x, 0.01), snappedf(v.y, 0.01)])
		out["mm"][nm] = pts
	print("DECOR_DUMP ", JSON.stringify(out))

# 식생 예산 트립와이어. 킷 모델은 텍스처가 있어 **메시별로 버킷(=드로우콜)이 갈리므로**
# 종을 늘리면 조용히 드로우콜이 는다 — 인스턴스·드로우콜·삼각형을 빌드 로그에 한 줄로 남긴다.
# 드로우콜은 노드 수가 아니라 **surface 수**다: 노드/MultiMesh 하나여도 Mesh에 surface가 여럿이면
# 그만큼 따로 제출된다(절차 메시는 1~2면이었지만 킷 glTF는 재질별로 갈린다) — 노드로 세면 과소 집계.
# (mm_draws = MultiMesh 드로우콜, node_draws = 개별 소품 MeshInstance 드로우콜)
func _perf() -> String:
	var mm_b := 0
	var mm_i := 0
	var mm_t := 0
	for c in get_children():
		var mmi := c as MultiMeshInstance3D
		if mmi == null:
			continue
		mm_b += _surfs(mmi.multimesh.mesh)
		mm_i += mmi.multimesh.instance_count
		mm_t += mmi.multimesh.instance_count * _tris(mmi.multimesh.mesh)
	var nm_n := [0, 0]
	_node_meshes(self, nm_n)
	return "mm_draws=%d mm_inst=%d mm_tris=%d | node_draws=%d node_tris=%d | total_tris=%d" \
		% [mm_b, mm_i, mm_t, nm_n[0], nm_n[1], mm_t + nm_n[1]]

func _surfs(m: Mesh) -> int:
	return 0 if m == null else m.get_surface_count()

func _tris(m: Mesh) -> int:
	if m == null:
		return 0
	var n := 0
	for i in m.get_surface_count():
		var a := m.surface_get_arrays(i)
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		n += (idx.size() if idx.size() > 0 else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n

func _node_meshes(node: Node, acc: Array) -> void:
	if node is MeshInstance3D:
		acc[0] += _surfs((node as MeshInstance3D).mesh)
		acc[1] += _tris((node as MeshInstance3D).mesh)
	for c in node.get_children():
		_node_meshes(c, acc)

func _count_collision(node: Node) -> int:
	var n := 0
	if (node is CollisionObject3D or node is CollisionShape3D) and not node.is_queued_for_deletion():
		n += 1
	for c in node.get_children():
		n += _count_collision(c)
	return n

# 가로등 점등: 실내등(interior.gd)과 같은 방식 — 태양 에너지가 떨어지면 켜진다.
func _process(_dt: float) -> void:
	if _lights.is_empty():
		return
	var f := DayNight.night_factor(GameClock.game_min / 60.0)
	for o in _lights:
		o.light_energy = LAMP_E * f
	if _glow != null:
		_glow.set_shader_parameter("glow", f)  # 유리 발광 판도 같은 계수로 함께 밝아진다

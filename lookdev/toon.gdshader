// 수채+연필 톤 셀 셰이딩 (레퍼런스: 사용자 컨셉 스케치)
// 딱딱한 계단 대신 부드러운 단조(soft terminator) + 따뜻한 그림자 틴트
// + 가장자리 물감 몰림(fresnel edge darkening).
shader_type spatial;
render_mode cull_back;

uniform vec4 albedo : source_color = vec4(0.9, 0.6, 0.7, 1.0);
// 모델 텍스처가 있으면 사용 (없으면 위 albedo 단색)
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform bool use_tex = false;
// 개체 색조 곱 (기본 흰=무변경, NPC 색상 구분용)
uniform vec4 char_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// 그림자 밝기(0=검정, 1=밝음) — 수채는 순검정 안 씀
uniform float shadow_level : hint_range(0.0, 1.0) = 0.55;
// 그림자에 섞을 따뜻한 색조(수채 그림자는 채색됨)
uniform vec4 shadow_tint : source_color = vec4(0.78, 0.66, 0.72, 1.0);
// 단조 경계 부드러움(0=하드셀, 0.2=수채)
uniform float terminator_soft : hint_range(0.01, 0.4) = 0.18;
// 가장자리 물감 몰림
uniform vec4 edge_pigment : source_color = vec4(0.55, 0.45, 0.52, 1.0);
uniform float edge_strength : hint_range(0.0, 1.0) = 0.28;
// 구매 킷 아틀라스를 마을 팔레트 대역으로 당기는 레버. 채도 **상한**이지 곱이 아니다 —
// 곱은 비율을 유지해서 제일 튀는 텍셀이 계속 제일 튀지만(벤치 0.69·게시판 0.85가 나란히
// 내려갈 뿐), 상한은 넘는 것만 깎아 이미 얌전한 텍셀은 원본 그대로 둔다 = 디테일 보존.
// 회색이 아니라 **최대 채널 쪽**으로 당긴다: 채도가 내려가면서 명도가 올라가는 이 방향이
// VILLAGE_SPEC 파스텔 시프트(채도 −15%p / 명도 +5%p)와 같은 방향이고, 최대 채널이 안 변하니
// char_tint가 잡아둔 정오 클리핑 상한도 그대로다.
// 기본 1.0 = 항등(분기도 uniform) → 캐릭터·기존 에셋은 옛 경로를 글자 그대로 통과한다.
// 선형 albedo 기준이다 — 화면(sRGB) 채도는 이보다 낮게 찍힌다(0.60 → 정오 실측 0.42~0.49).
uniform float sat_cap : hint_range(0.0, 1.0) = 1.0;
// 킷 아틀라스 **밝기** 정합 레버 — char_tint(밝은 킷을 끌어내리는 곱, Kenney 1.0 → 0.72)의 반대 방향.
// 식생 킷(Tiny Treats)은 반대로 마을보다 훨씬 어둡다: 수관 화면 실측 (72,128,76) vs 마을 절차
// 수관 (195,212,169). 채도(sat_cap)로는 못 올린다 — 그건 최대 채널 쪽으로 당길 뿐이라 명도 천장이
// 최대 채널에 묶이고, 결과는 회색조 나무가 된다(실측 계산). 그래서 hue·비율을 보존하는 순수 곱을 둔다.
// 기본 1.0 = 항등 → 캐릭터·기존 에셋은 옛 경로를 글자 그대로 통과한다(sat_cap과 같은 규약).
uniform float val_gain : hint_range(0.25, 4.0) = 1.0;
// ── 잎 전용 보정(킷 나무 단풍) ───────────────────────────────────────
// 킷 나무는 **표면이 한 장**이라(수관·수피가 같은 머티리얼) 단풍 보정이 줄기까지 물들였다.
// 잎은 초록·수피는 갈색이므로 **색만 보고 갈린다** — 기하 측정도 메시 수술도 필요 없다.
// 아틀라스 실측(tree/tree_large 전 정점 UV, 선형 초록도 = G − max(R,B)):
//   수피 텍셀 4종 −0.317 ~ −0.254  |  잎 텍셀 +0.079 ~ +0.392  → 사이가 0.33 비어 있다.
//   두 UV 섬이 아틀라스에서 멀고(수피 x942~977·y95~218 / 잎 x169~·y333~397) **경계를 걸친
//   삼각형이 0개**(320·500개 전수 확인)라 보간으로 새는 프래그먼트도 없다.
// green_gate = 초록 판정 문턱. **0 = 항등**(게이트 없음) → 캐릭터·가구·킷 소품·겨울 서리
// 사본은 옛 경로를 글자 그대로 통과한다(sat_cap·val_gain과 같은 규약).
// 게이트가 켜지면 **잎 텍셀만** leaf_sat·leaf_tint로 다시 보정하고, 나머지 텍셀은
// sat_cap·char_tint(= 킷 기본 보정)를 그대로 탄다 = 줄기가 사계절 같은 색으로 남는다.
// 되돌린 시도: 처음엔 게이트 밖을 **원본 텍셀**로 흘렸다(uniform 하나로 끝나서). 실측에서
// 실패했다 — 킷 수피 텍셀 자체가 채도 높은 테라코타(166,101,70)라, 화면 (200,112,70)으로
// 단풍 전 (218,117,58)에서 거의 안 움직였다. 수피를 얌전하게 만드는 건 tint가 아니라
// **sat_cap 0.60**이었다(여름 줄기 실측 (189,138,110)). 그래서 두 벌을 다 태우는 지금 판이다.
uniform float green_gate = 0.0;
uniform float leaf_sat : hint_range(0.0, 1.0) = 1.0;
uniform vec4 leaf_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// 동물의 숲식 월드 곡률 (거리²만큼 지평선을 아래로 휘게)
uniform float curve_strength = 0.006;

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.y -= curve_strength * v.z * v.z;
	POSITION = PROJECTION_MATRIX * v;
}

// 보정 한 벌: 채도 상한 → 밝기 곱 → 색조. 게이트가 켜지면 fragment가 두 번 부른다(킷 기본 / 잎).
vec3 grade(vec3 src, float sat, float gain, vec3 tint) {
	if (sat < 1.0) {
		float mx = max(src.r, max(src.g, src.b));
		float sv = (mx - min(src.r, min(src.g, src.b))) / max(mx, 1e-4);
		src = mix(vec3(mx), src, min(1.0, sat / max(sv, 1e-4)));
	}
	// 정오 직광 클리핑 상한(char_tint가 잡아둔 것)을 넘지 않게 곱한 뒤 자른다.
	return min(src * gain, vec3(1.0)) * tint;
}

void fragment() {
	vec3 raw = use_tex ? texture(albedo_tex, UV).rgb : albedo.rgb;
	vec3 base = grade(raw, sat_cap, val_gain, char_tint.rgb);
	if (green_gate > 0.0) {
		// 하드 컷이면 밉맵·필터가 섞어 낸 경계 텍셀에서 계단이 난다 → ±0.05 대역으로 부드럽게.
		// 실측 공백이 0.33이라 이 대역은 수피(−0.25 이하)도 잎(+0.079 이상)도 건드리지 않는다.
		base = mix(base, grade(raw, leaf_sat, val_gain, leaf_tint.rgb),
			smoothstep(green_gate - 0.05, green_gate + 0.05, raw.g - max(raw.r, raw.b)));
	}
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(base, edge_pigment.rgb, fres * edge_strength);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT)) * 0.5 + 0.5;
	// 부드러운 단조: 경계 근처만 완만, 나머진 평평 (수채 느낌)
	float t = smoothstep(0.5 - terminator_soft, 0.5 + terminator_soft, ndl);
	float shade = mix(shadow_level, 1.0, t);
	vec3 tint = mix(shadow_tint.rgb, vec3(1.0), t);  // 그림자쪽에 따뜻한 색
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * shade * tint;
}

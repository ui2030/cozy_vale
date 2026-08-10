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
// 동물의 숲식 월드 곡률 (거리²만큼 지평선을 아래로 휘게)
uniform float curve_strength = 0.006;

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.y -= curve_strength * v.z * v.z;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	vec3 src = use_tex ? texture(albedo_tex, UV).rgb : albedo.rgb;
	if (sat_cap < 1.0) {
		float mx = max(src.r, max(src.g, src.b));
		float sv = (mx - min(src.r, min(src.g, src.b))) / max(mx, 1e-4);
		src = mix(vec3(mx), src, min(1.0, sat_cap / max(sv, 1e-4)));
	}
	vec3 base = src * char_tint.rgb;
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

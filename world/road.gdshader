// 흙길: 하드 엣지 직사각 박스 → 가장자리가 풀에 스미는 부드러운 길.
// 침식은 **alpha scissor(discard) — 불투명 파이프라인**이다. 길 박스는 지면과 거의 같은 평면에
// 겹쳐 깔리는데 알파 블렌드로 깔면 소팅·블렌딩이 깨진다(Codex MUST-FIX 1).
//
// 형상: 모델 xz의 라운드 사각 SDF(끝단 모서리 라운딩) − 월드 xz 노이즈(fbm) 만큼 안쪽으로 갉아낸다.
//   · SDF는 모델 좌표 = 박스 회전과 무관하게 길 폭/길이에 딱 맞는다(half_ext는 world.gd가 넣어 준다).
//   · 노이즈는 월드 좌표 = 길이 꺾이는 교차부에서도 침식 무늬가 이어진다.
// 박스 옆면(|x|=half)·끝면은 SDF 경계라 항상 discard된다 = 0.085 두께 턱이 사라진다(의도).
// 곡률 vertex는 toon.gdshader와 동일식(빠지면 길만 지평선에서 뜬다).
shader_type spatial;
render_mode cull_back;

uniform vec4 albedo : source_color = vec4(0.700, 0.619, 0.476, 1.0);      // 파스텔 모래빛
uniform vec4 edge_color : source_color = vec4(0.720, 0.673, 0.590, 1.0);  // 가장자리 — 풀로 옅어지는 톤
uniform vec2 half_ext = vec2(1.2, 6.0);  // 길 박스 반크기(모델 xz). world.gd _road가 박스마다 설정.
uniform float corner = 0.75;   // 끝단 모서리 라운딩 반경(m) — 반폭 1.2보다 작아야 한다
uniform float erode = 0.45;    // 노이즈 침식 최대 깊이(m)
// 가장자리 색 스밈 폭(m). 흙길은 **하드엣지**여야 한다 — 0.55는 폭2.4 길의 반폭(1.2)에 육박해
// 길 전체가 edge_color로 번진 에어브러시 얼룩이 됐다(실측 audit2/hall·windmill·open_res_h12).
// 0.10이면 edge_color가 discard 경계에 붙은 얇은 림으로만 남아 플랫 2톤 툰과 붙는다.
// 물결치는 윤곽은 fade가 아니라 erode(노이즈 침식 + 불투명 discard)가 만든다 — 그쪽은 불변.
// 부드러워야 하는 판(해변 젖은 모래 띠)은 beach.gd가 이 uniform을 직접 올려 쓴다(0.35).
uniform float fade = 0.10;
uniform float curve_strength = 0.006;

// toon.gdshader와 같은 수채 단조
uniform float shadow_level : hint_range(0.0, 1.0) = 0.55;
uniform vec4 shadow_tint : source_color = vec4(0.78, 0.66, 0.72, 1.0);
uniform float terminator_soft : hint_range(0.01, 0.4) = 0.18;

varying vec3 mpos;
varying vec2 wpos;

float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x),
		mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

// 3옥타브 = 큰 굽이(가장자리 곡선) + 잔 부스러기(풀에 스민 알갱이).
float fbm(vec2 p) {
	return 0.55 * vnoise(p * 0.55) + 0.30 * vnoise(p * 1.6) + 0.15 * vnoise(p * 4.2);
}

void vertex() {
	mpos = VERTEX;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.y -= curve_strength * v.z * v.z;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	vec2 q = abs(mpos.xz) - (half_ext - vec2(corner));
	float sd = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - corner;
	float inside = -sd;  // 경계에서 안쪽으로의 거리(m)
	if (inside < fbm(wpos) * erode) {
		discard;
	}
	ALBEDO = mix(edge_color.rgb, albedo.rgb, smoothstep(0.0, fade, inside - erode * 0.5));
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT)) * 0.5 + 0.5;
	float t = smoothstep(0.5 - terminator_soft, 0.5 + terminator_soft, ndl);
	float shade = mix(shadow_level, 1.0, t);
	vec3 tint = mix(shadow_tint.rgb, vec3(1.0), t);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * shade * tint;
}

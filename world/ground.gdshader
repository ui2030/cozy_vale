// 초지 바닥: 은은한 2톤 풀 패턴(둥근 체커 + 칸별 명도 변주). 텍스처 파일 0(절차 패턴).
// plaza.gdshader와 같은 결 — 곡률 vertex + toon light()를 그대로 쓴다(빠뜨리면 바닥만 지평선에서 뜬다).
//
// 계약: base color는 uniform `albedo` — world.gd _apply_season의 ground_color()(초지/눈)가 구동한다.
// 패턴은 **감광 방향으로만** 넣는다(밝히지 않는다). 정오 수평면은 albedo 0.72쯤에서 이미 255에
// 가까워서(실측: albedo 0.80 초지 = G채널 255 클리핑), 밝은 칸을 더 올리면 패턴이 통째로 날아간다.
shader_type spatial;
render_mode cull_back;

uniform vec4 albedo : source_color = vec4(0.627, 0.72, 0.576, 1.0);
uniform float pattern : hint_range(0.0, 1.0) = 1.0;  // 계절 강도 — 겨울(눈)은 절반(요철 느낌만)
uniform float cell = 1.4;         // 칸 한 변(m). 게임 카메라 화각에서 ~100px = "질감" 스케일
uniform float shade_depth = 0.11;  // 어두운 칸 감광폭(albedo 배율 1-이값)
uniform float mottle = 0.04;      // 칸별 추가 변주(격자로 안 읽히게)
// 절차 패턴은 밉맵이 없어 멀어지면 픽셀 단위로 깜빡인다(걸을 때 지글거림). 거리로 녹여 없앤다.
uniform vec2 fade_dist = vec2(22.0, 48.0);
uniform float curve_strength = 0.006;  // toon.gdshader와 동일 월드 곡률

// toon.gdshader와 같은 수채 단조
uniform float shadow_level : hint_range(0.0, 1.0) = 0.55;
uniform vec4 shadow_tint : source_color = vec4(0.78, 0.66, 0.72, 1.0);
uniform float terminator_soft : hint_range(0.01, 0.4) = 0.18;

const float PI_C = 3.14159265359;

varying vec3 mpos;
varying float vdist;  // 카메라까지 거리(뷰 공간) — 패턴 거리 페이드

float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void vertex() {
	mpos = VERTEX;
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vdist = length(v.xyz);
	v.y -= curve_strength * v.z * v.z;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	vec2 c = mpos.xz / cell;
	// sin·sin = 1칸 간격 체커. smoothstep으로 모서리를 둥글려 각진 격자가 안 보이게 한다.
	float k = sin(c.x * PI_C) * sin(c.y * PI_C);
	float t = smoothstep(-0.5, 0.5, k);
	float h = hash2(floor(c));
	float d = pattern * (shade_depth * (1.0 - t) + mottle * h)
		* (1.0 - smoothstep(fade_dist.x, fade_dist.y, vdist));
	ALBEDO = albedo.rgb * (1.0 - d);
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

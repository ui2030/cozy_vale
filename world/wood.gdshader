// 절차 목재: 나이테 + 결. 텍스처 파일 0 (bridge.gdshader 석조 패턴과 같은 수법).
// 유저 지시: "나무 의자면 나무의 결대로 자른 나무의자니까 나이테가 있어야겠지".
//
// 원리는 실제 제재목 그대로다 — 통나무엔 **수(pith)를 중심으로 한 동심 나이테**가 있고,
// 거기서 판을 켜면 자른 방향에 따라 같은 무늬가 다르게 보인다:
//   · 마구리(결 축과 마주보는 면) = 동심원 그대로
//   · 널면(결 축과 나란한 면)     = 그 동심원을 비스듬히 자른 나뭇결 줄무늬
// 그래서 면마다 다른 식을 쓰지 않는다. **단면 반지름 하나**로 두 모양이 저절로 나온다.
// 곡률 vertex·조명 light()는 toon.gdshader와 동일식(빠뜨리면 목재만 지평선에서 뜬다).
shader_type spatial;
render_mode cull_back;

uniform vec4 wood_color : source_color = vec4(0.590, 0.480, 0.362, 1.0);  // 춘재(밝은 띠)
uniform vec4 ring_color : source_color = vec4(0.470, 0.372, 0.283, 1.0);  // 추재(어두운 띠)
// 결이 흐르는 축 = 그 조각의 최장변. 호출부가 크기에서 뽑아 넣는다(ToonChar.solid_or_wood).
uniform vec3 grain_dir = vec3(1.0, 0.0, 0.0);
// 나이테 중심. **중앙이면 안 된다** — 정중앙이면 널면 무늬가 좌우 대칭 줄이 돼 인쇄물처럼 보인다.
uniform vec2 pith = vec2(0.42, 0.17);
// m당 나이테 수. 1차 실측(7.0)은 문 0.9폭에 띠가 2개만 떠서 "나뭇결"이 아니라 "색이 두 칸으로
// 갈린 판"으로 보였다 — 유저가 원한 건 그 반대다. 14면 문에 11줄, 궤짝 마구리에 동심원이 뜬다.
uniform float ring_freq = 14.0;
uniform float ring_sharp = 0.42;  // 추재 띠 폭(0=실선, 1=반반). 촘촘해진 만큼 띠는 얇게
uniform float wobble = 0.10;      // 결 축을 따라 흔드는 폭 = 무늿결(cathedral) 아치를 만든다
// 1차 실측 0.55는 추재 대비(darkened 0.21)와 곱해져 화면 대비가 11%뿐이라 안 보였다.
uniform float ring_strength = 0.85;
uniform float curve_strength = 0.006;  // toon.gdshader와 동일 월드 곡률

// toon.gdshader와 같은 수채 단조 파라미터
uniform float shadow_level : hint_range(0.0, 1.0) = 0.55;
uniform vec4 shadow_tint : source_color = vec4(0.78, 0.66, 0.72, 1.0);
uniform float terminator_soft : hint_range(0.01, 0.4) = 0.18;

varying vec3 mpos;  // 모델좌표 — 조각마다 회전이 걸려도 결이 따라 돈다(월드 아님)

void vertex() {
	mpos = VERTEX;
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.y -= curve_strength * v.z * v.z;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	vec3 a = normalize(grain_dir);
	// 결 축에 수직인 단면 좌표계
	vec3 up = abs(a.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 u = normalize(cross(a, up));
	vec3 w = cross(a, u);
	float s = dot(mpos, a);                                  // 결을 따라 간 거리
	vec2 c = vec2(dot(mpos, u), dot(mpos, w)) - pith;        // 수에서 잰 단면 위치
	// 결 축을 따라 반지름을 흔든다 = 통나무가 완전한 원기둥이 아니라는 뜻. 이게 널면에서
	// 무늿결 아치가 되고, 안 넣으면 널면 무늬가 자로 그은 평행선이 된다.
	float r = length(c) + wobble * (sin(s * 2.3) * 0.6 + sin(s * 0.9 + 1.7) * 0.4);

	float t = fract(r * ring_freq);
	float band = smoothstep(1.0 - ring_sharp, 1.0, 1.0 - abs(2.0 * t - 1.0));
	// 원거리 앨리어싱 차단: 나이테 주기가 픽셀 크기에 가까워지면 무늬를 지운다.
	// (이 프로젝트는 외곽선 셸이 반픽셀에서 점선으로 깨져 통째로 버린 전례가 있다.)
	band *= 1.0 - smoothstep(0.30, 0.50, fwidth(r * ring_freq));

	ALBEDO = mix(wood_color.rgb, ring_color.rgb, band * ring_strength);
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

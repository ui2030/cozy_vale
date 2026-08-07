// 바람의 지휘봉풍 툰 물: 절차적 value noise 하이라이트 패치가 흐르는 플랫 2단 톤.
// 텍스처 없음(셰이더 내 노이즈). 곡률 vertex는 toon.gdshader와 동일 — 정적 지형과 어긋나지 않게.
shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.50, 0.72, 0.85, 1.0);       // C_WATER(마을 팔레트)
uniform vec4 highlight_color : source_color = vec4(0.74, 0.89, 0.97, 1.0);  // 밝은 물감 패치
// 노을·새벽 수면(하늘빛 반사). 청록 albedo × 주황 태양광 = 올리브 — 곱하기 전에 albedo를
// 하늘 쪽으로 옮겨야 한다. B>G인 연보라빛 분홍인 이유: 노을 조명이 ≈(R0.67 G0.49 B0.37)이라
// B를 깎으므로 미리 되갚아야 화면에서 장밋빛으로 앉는다(주황을 그대로 넣으면 붉은 찰흙, 실측).
uniform vec4 warm_color : source_color = vec4(0.90, 0.65, 0.71, 1.0);
uniform vec4 warm_highlight : source_color = vec4(1.00, 0.89, 0.84, 1.0);
uniform float warm_glow = 0.18;     // 반사광 가산(태양이 지평선이라 수면 N·L≈0 = 디퓨즈만으론 어둡고 탁하다).
                                    // 올리면 하늘처럼 밝아지지만 0.3부터는 수평선이 하늘에 붙는다(실측).
uniform float noise_scale = 0.6;    // 패치 크기(작을수록 큰 패치)
uniform float flow_speed = 0.06;    // 흐름 속도
uniform float coverage : hint_range(0.0, 1.0) = 0.60;  // 하이라이트 임계(클수록 패치 좁음)
uniform float curve_strength = 0.006;  // toon.gdshader와 동일 월드 곡률
global uniform float time_of_day;   // day_night.gd가 매 프레임 주입(0~24 연속). 하늘과 같은 단일 출처.

varying vec2 world_xz;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

// value noise (bilinear + smoothstep)
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;  // 월드좌표로 연못·강 패치 크기 통일
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.y -= curve_strength * v.z * v.z;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	vec2 t = vec2(TIME * flow_speed, TIME * flow_speed * 0.7);
	float n = vnoise(world_xz * noise_scale + t);
	n = n * 0.65 + vnoise(world_xz * noise_scale * 2.0 - t * 1.3) * 0.35;
	float hl = step(coverage, n);  // 플랫 2단 톤(그라데이션 없음)
	// 따뜻함 가중: sky.gdshader의 dusk/dawn 가우시안과 같은 식 — 시간대 if 분기 없음.
	// 정오엔 1e-5 수준(8비트 1/255=0.004 훨씬 아래) = 낮 룩 불변. 밤(21시 0.08)도 거의 청색 유지.
	float warm = clamp(exp(-pow((time_of_day - 18.3) / 1.7, 2.0))
					 + exp(-pow((time_of_day - 6.8) / 1.5, 2.0)), 0.0, 1.0);
	vec3 col = mix(mix(base_color.rgb, highlight_color.rgb, hl),
				   mix(warm_color.rgb, warm_highlight.rgb, hl), warm * 0.9);
	ALBEDO = col;
	EMISSION = col * warm * warm_glow;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

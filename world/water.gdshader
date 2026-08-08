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
// 곡률이 멈추는 뷰 깊이(m). 기본값은 사실상 무한 = 연못·강은 지금까지와 완전히 같다.
// 바다만 유한값을 넣는다: 툰 곡률은 원경을 아래로 말아 넣어 수면을 크레스트에서 끊으므로,
// 넓은 물은 화면 중간의 얇은 띠로 끝난다. 이 깊이 밖을 평평하게 두면 수평선이 선다.
uniform float curve_cap = 1.0e4;   // 기본 10km = 어떤 컷에서도 캡에 닿지 않는다(연못·강 불변)
// ── 밀려오는 파도선 (해변 전용 — foam_gap 0이면 분기 자체가 꺼진다) ──
uniform float foam_gap = 0.0;       // 파도선 간격(m). 0 = 끄기
uniform float foam_z = 0.0;         // 위상 기준 월드 z = 물가선(여기서 파도가 부서진다)
uniform float foam_duty : hint_range(0.0, 0.5) = 0.13;  // 간격 중 흰 선이 차지하는 비율
uniform float foam_speed = 0.045;   // 물가 쪽(+z)으로 밀려오는 속도(간격/초)
uniform vec4 foam_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
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
	v.y -= curve_strength * min(v.z * v.z, curve_cap * curve_cap);
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
	// 파도선: 물가선을 위상 0으로 삼아 일정 간격으로 반복하고 물가 쪽으로 흐른다.
	// 같은 value noise로 흔들어 자로 그은 직선이 아니라 굽이치는 물마루가 된다.
	// 원경(캡 밖)에선 간격이 픽셀 이하로 압축돼 모아레가 되므로 그 전에 녹여 없앤다.
	if (foam_gap > 0.0) {
		float wob = (vnoise(vec2(world_xz.x * 0.16, TIME * 0.06)) - 0.5) * foam_gap * 0.5;
		float ph = fract((world_xz.y - foam_z + wob) / foam_gap - TIME * foam_speed);
		// 0.85·cap(=34)까지 온전히, 1.3·cap(=52)에서 완전히 녹는다 — 도착 지점에서 물가선의
		// 뷰 깊이가 이미 23이라 이보다 일찍 시작하면 파도선이 물가에서부터 유령이 된다(실측).
		float near = 1.0 - smoothstep(0.85, 1.3, -VERTEX.z / curve_cap);
		// 노을엔 흰 선이 물 자체의 웜 하이라이트에 묻힌다 — 절반만 물들여 한 단 더 밝게 남긴다.
		col = mix(col, mix(foam_color.rgb, warm_highlight.rgb, warm * 0.5), step(ph, foam_duty) * near);
	}
	ALBEDO = col;
	EMISSION = col * warm * warm_glow;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

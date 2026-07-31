// 광장 판석 바닥: 분수를 중심으로 한 방사 배열 석재 슬래브. 텍스처 파일 0(절차 패턴).
// 크림 슬래브 + 회색 줄눈의 플랫 2톤(그라데이션 없음) — water.gdshader 전례와 같은 결.
// 곡률 vertex는 toon.gdshader와 동일식(빠뜨리면 지평선에서 바닥만 뜬다).
// 조명(light)도 toon.gdshader와 같은 소프트 단조 — 광장만 다른 그림체가 되지 않게.
shader_type spatial;
render_mode cull_back;

uniform vec4 slab_color : source_color = vec4(0.74, 0.68, 0.58, 1.0);   // 크림 #E6D9C3 계열
// (정오 태양이 수평면을 정면으로 때려 0.90 크림은 흰색으로 클리핑된다 — 픽셀 실측 후 하향)
uniform vec4 joint_color : source_color = vec4(0.48, 0.44, 0.40, 1.0);  // 회색 줄눈
uniform float ring_width = 0.82;    // 링(반경 방향) 폭
uniform float slab_arc = 0.95;      // 슬래브 1장의 목표 호 길이 → 링별 분할수가 반경 비례
uniform float joint = 0.09;         // 줄눈 두께(모델 단위)
uniform float tone_var = 0.065;      // 판석마다 명도 변주 폭(수제 석재 느낌)
uniform float curve_strength = 0.006;  // toon.gdshader와 동일 월드 곡률

// toon.gdshader와 같은 수채 단조 파라미터
uniform float shadow_level : hint_range(0.0, 1.0) = 0.55;
uniform vec4 shadow_tint : source_color = vec4(0.78, 0.66, 0.72, 1.0);
uniform float terminator_soft : hint_range(0.01, 0.4) = 0.18;

const float TAU_C = 6.28318530718;

varying vec3 mpos;  // 모델좌표 — 회전·스케일이 걸려도 패턴이 뭉개지지 않게(월드 아님)

float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void vertex() {
	mpos = VERTEX;
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.y -= curve_strength * v.z * v.z;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	vec2 p = mpos.xz;
	float r = max(length(p), 0.001);
	float ring = floor(r / ring_width);
	float rf = fract(r / ring_width);
	// 링 둘레를 slab_arc 길이로 나눈 수 = 바깥 링일수록 판석이 많아진다(방사 배열).
	float n = max(6.0, floor(TAU_C * (ring + 0.5) * ring_width / slab_arc));
	// 링마다 반 칸 어긋뜨려 줄눈이 일직선으로 겹치지 않게(벽돌 쌓기).
	float u = fract(atan(p.y, p.x) / TAU_C + 0.5) * n + mod(ring, 2.0) * 0.5;
	float seg = floor(u);
	float uf = fract(u);

	float jr = joint / ring_width;              // 반경 방향 줄눈 폭(rf 단위)
	float ja = joint * n / (TAU_C * r);         // 각 방향 줄눈 폭(uf 단위) — 반경 보정
	float is_joint = clamp(step(min(rf, 1.0 - rf), jr * 0.5)
		+ step(min(uf, 1.0 - uf), ja * 0.5), 0.0, 1.0);

	float t = (hash2(vec2(seg, ring)) - 0.5) * 2.0 * tone_var;
	ALBEDO = mix(slab_color.rgb + vec3(t), joint_color.rgb, is_joint);
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

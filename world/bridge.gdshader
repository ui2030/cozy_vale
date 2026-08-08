// 돌다리 석조: 벽돌 켜 쌓기(masonry) 패턴. 텍스처 파일 0(절차 패턴).
// 붉은 벽돌 금지(유저 지시). 색·켜 크기·줄눈 대비를 **광장 판석(plaza.gdshader)에 맞춘다** —
// 마을 전체가 무텍스처 파스텔인데 다리만 회백색 실사 벽돌이라 한 화면에 그림체가 둘이었다.
// 곡률 vertex·조명 light()는 toon.gdshader와 동일식(빠뜨리면 다리만 지평선에서 뜬다).
shader_type spatial;
render_mode cull_back;

// plaza.gdshader slab_color와 같은 웜 크림. 옛 (0.735,0.722,0.700)은 무채에 가까워서 정오
// 직광면에서 R·G·B가 한꺼번에 포화해 화면에 (250,247,242) = 순백으로 나왔다(실측 pond_h12).
// 광장 판석은 같은 명도라도 B가 낮아 포화 후에도 (255,244,214) 크림으로 남는다 = 그 값을 쓴다.
uniform vec4 stone_color : source_color = vec4(0.740, 0.680, 0.580, 1.0);  // 석재 웜크림
// 줄눈은 광장 판석 줄눈(0.48,0.44,0.40)의 hue를 유지한 채 한 단 밝게 — 판석은 수평면이라
// 슬래브가 255로 포화해 대비가 눌리지만, 다리 난간·아치 벽은 수직면이라 포화가 없다.
// 같은 albedo 쌍을 그대로 쓰면 다리 쪽 줄눈이 더 세게 읽힌다(체감 대비를 광장에 맞추는 보정).
uniform vec4 joint_color : source_color = vec4(0.560, 0.510, 0.450, 1.0);  // 줄눈(같은 hue 한 단 아래)
// 켜를 광장 판석 스케일(0.82×0.95)에 가깝게 키운다. 옛 0.30×0.62는 면적당 벽돌이 2배여서
// 패턴 밀도가 "사진 텍스처"로 읽혔다. joint/course = 11.9% ≒ 광장의 11%(줄눈 굵기 비율 일치).
uniform float course = 0.42;   // 한 켜(row) 높이
uniform float brick = 0.88;    // 벽돌 한 장 길이
uniform float joint = 0.05;    // 줄눈 두께(모델 단위)
uniform float tone_var = 0.065; // 돌마다 명도 변주(수제 석재 느낌) — 광장 판석과 같은 폭
uniform float curve_strength = 0.006;  // toon.gdshader와 동일 월드 곡률
// 휜 데크·난간은 세그먼트 박스로 쪼개져 있어 모델좌표가 조각마다 0에서 다시 시작한다.
// 조각 중심까지의 누적 호길이를 넣어 주면 벽돌 켜가 리셋되지 않고 이어진다(0 = 통짜 지오메트리).
uniform vec2 uv_shift = vec2(0.0);

// toon.gdshader와 같은 수채 단조 파라미터
uniform float shadow_level : hint_range(0.0, 1.0) = 0.55;
uniform vec4 shadow_tint : source_color = vec4(0.78, 0.66, 0.72, 1.0);
uniform float terminator_soft : hint_range(0.01, 0.4) = 0.18;

varying vec3 mpos;   // 모델좌표 — 다리마다 y회전이 걸려도 패턴이 뭉개지지 않게(월드 아님)
varying vec3 mnorm;  // 모델공간 법선 — 면 방향에 따라 켜 방향을 고른다

float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void vertex() {
	mpos = VERTEX;
	mnorm = NORMAL;
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.y -= curve_strength * v.z * v.z;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	// 면 방향으로 투영면 선택: 수평면(데크 상면)은 포장돌, 수직면(난간·아치 벽)은 가로 켜 쌓기.
	// 아치 소핏(곡면)은 법선이 돌지만 켜 방향(y)은 양쪽 분기 모두 같아 이어져 보인다.
	// **위를 보는 면만** 포장돌이다(abs가 아니라 부호 있는 y). 아치 소핏 관정은 법선이 아래를
	// 향해 abs로는 데크 상면과 같은 평면투영을 받았고, 그러면 켜가 터널 폭(mpos.z) 방향으로
	// 갈려 아치 안팎 벽돌 크기가 달라 보였다(실측 arch_h12) — 벽과 같은 입면투영으로 넘긴다.
	vec3 nn = normalize(mnorm);
	vec3 n = abs(nn);
	vec2 uv;
	if (nn.y > max(n.x, n.z)) {
		uv = vec2(mpos.x, mpos.z);
	} else if (n.x > n.z) {
		uv = vec2(mpos.z, mpos.y);
	} else {
		uv = vec2(mpos.x, mpos.y);
	}
	uv += uv_shift;
	float rowf = uv.y / course;
	float row = floor(rowf);
	float u = uv.x / brick + mod(row, 2.0) * 0.5;  // 켜마다 반 장 어긋남(벽돌 쌓기)
	float col = floor(u);
	float fu = fract(u);
	float fv = fract(rowf);
	float is_joint = clamp(step(min(fu, 1.0 - fu), joint / brick * 0.5)
		+ step(min(fv, 1.0 - fv), joint / course * 0.5), 0.0, 1.0);

	float t = (hash2(vec2(col, row)) - 0.5) * 2.0 * tone_var;
	ALBEDO = mix(stone_color.rgb + vec3(t), joint_color.rgb, is_joint);
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

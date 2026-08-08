// 접지 그림자 — 오브젝트 밑에 깔리는 어두운 타원 판 하나(곱셈 블렌드).
// 태양광 그림자가 아니라 이걸 쓰는 이유: 해변엔 태양광 그림자가 아예 안 온다. toon.gdshader가
// vertex()에서 v.y -= 0.006·z²로 POSITION을 직접 쓰는데, 그림자(깊이) 패스에선 그 z가 광원 기준이
// 되어 원점에서 먼 존은 깊이가 통째로 뒤틀린다 — 마을(원점)은 그림자가 나오지만 해변(원점에서
// 212)은 정오·노을 어느 시각에도 0이다(실측 ground_fix/probe_hall_h18 vs probe_hut_h18).
// 지면과 **같은 월드 곡률**을 써야 판이 원경에서 지면에서 떨어져 뜨지 않는다(toon/ground와 동일 식).
// 곱셈이라 지면 색조(모래 웜톤·초지 그린)를 보존한다 — 판이 회색 스티커로 얹히지 않는다.
shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled;

// 코어에서 지면을 이만큼 곱한다(=밝기). 순검정 금지 — 툰 파스텔 그림자는 색이 있다
// (toon.gdshader shadow_tint가 분홍 계열인 것과 같은 규약).
uniform vec4 tint : source_color = vec4(0.66, 0.58, 0.62, 1.0);
uniform float core : hint_range(0.0, 1.0) = 0.8;  // 이 반경까지 균일, 밖은 판 끝까지 페이드
uniform float curve_strength = 0.006;             // toon.gdshader와 동일 월드 곡률

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.y -= curve_strength * v.z * v.z;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;               // 판 중심 0 → 변 중앙 1
	ALBEDO = mix(vec3(1.0), tint.rgb, 1.0 - smoothstep(core, 1.0, d));
}

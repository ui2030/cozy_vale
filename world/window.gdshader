// 밤 창불빛 판 — 벽에 붙는 작은 발광 판. contact.gdshader(접지 그림자)의 대칭짝이다:
// 같은 unshaded + 같은 월드 곡률, 블렌드만 곱셈(어둡게)이 아니라 알파(밝게).
//
// unshaded인 이유: 툰 light()를 타면 밤엔 창도 같이 어두워져 "불 켜진 창"으로 안 읽힌다.
// 곡률이 필수인 이유: 건물은 toon.gdshader가 v.y -= 0.006·z²로 가라앉히는데 창만 제자리면
// 원경 집에서 창이 지붕 위 허공에 줄줄이 떠 있다(실측 1차 after — 거리 20에서 2.4 부양).
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.86, 0.55, 1.0);
uniform float glow : hint_range(0.0, 1.0) = 0.0;  // day_night.night_factor — 낮 0 = 완전 투명
uniform float curve_strength = 0.006;             // toon.gdshader와 동일 월드 곡률

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.y -= curve_strength * v.z * v.z;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = glow;
}

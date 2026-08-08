// 창 판 — 판 하나가 낮 창(유리 + 창틀·창살)과 밤 창불빛을 겸한다.
// contact.gdshader(접지 그림자)의 대칭짝이다: 같은 unshaded + 같은 월드 곡률, 블렌드만
// 곱셈(어둡게)이 아니라 알파(밝게).
//
// unshaded인 이유(밤): 툰 light()를 타면 밤엔 창도 같이 어두워져 "불 켜진 창"으로 안 읽힌다.
// unshaded인 이유(낮): 벽토(C_WALL)는 정오 직광면에서 255로 포화하는데, 창은 조명을 안 타므로
// day_tint/frame_tint 값이 화면에 거의 그대로 남는다 = 하얗게 뜬 벽 위에서도 대비가 안 죽는다.
// 곡률이 필수인 이유: 건물은 toon.gdshader가 v.y -= 0.006·z²로 가라앉히는데 창만 제자리면
// 원경 집에서 창이 지붕 위 허공에 줄줄이 떠 있다(실측 1차 after — 거리 20에서 2.4 부양).
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.86, 0.55, 1.0);  // 밤 발광색(유리)
// 낮 유리색. a=0이면 낮엔 아예 안 그린다 = 가로등 등갓 발광 판의 기존 동작(decor.gd _glow_mat).
uniform vec4 day_tint : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 frame_tint : source_color = vec4(0.30, 0.22, 0.26, 1.0);  // 창틀·창살
uniform float frame_w : hint_range(0.0, 0.5) = 0.0;  // 면 UV 기준 창틀 두께. 0 = 창틀 없음
uniform float glow : hint_range(0.0, 1.0) = 0.0;  // day_night.night_factor — 1 = 한밤
uniform float curve_strength = 0.006;             // toon.gdshader와 동일 월드 곡률

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.y -= curve_strength * v.z * v.z;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	// BoxMesh는 여섯 면을 3×2 아틀라스로 편다 → ×(3,2)의 소수부가 면마다 0..1 로컬 UV다.
	vec2 f = fract(UV * vec2(3.0, 2.0));
	float border = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));  // 면 테두리까지 거리
	float mullion = min(abs(f.x - 0.5), abs(f.y - 0.5));           // 창살 십자
	vec3 col = mix(day_tint.rgb, tint.rgb, glow);
	if (min(border, mullion) < frame_w) {
		col = frame_tint.rgb;
	}
	ALBEDO = col;
	ALPHA = max(glow, day_tint.a);
}

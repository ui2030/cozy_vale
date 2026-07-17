// inverted-hull 외곽선 (DESIGN.md 11.5)
// 메시를 법선 방향으로 살짝 키우고 앞면을 컬링해 검은 테두리만 남김.
shader_type spatial;
render_mode cull_front, unshaded;

uniform float width : hint_range(0.0, 0.1) = 0.02;
uniform vec4 line_color : source_color = vec4(0.06, 0.05, 0.08, 1.0);

void vertex() {
	VERTEX += normalize(NORMAL) * width;
}

void fragment() {
	ALBEDO = line_color.rgb;
}

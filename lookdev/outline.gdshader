// 연필 톤 외곽선 (레퍼런스: 손그림 스케치)
// inverted-hull. 순검정 대신 따뜻한 연필 회색, 얇게.
shader_type spatial;
render_mode cull_front, unshaded;

uniform float width : hint_range(0.0, 0.1) = 0.014;
uniform vec4 line_color : source_color = vec4(0.34, 0.29, 0.33, 1.0);

void vertex() {
	VERTEX += normalize(NORMAL) * width;
}

void fragment() {
	ALBEDO = line_color.rgb;
}

// 셀 셰이딩 — 2~3단 계단식 (DESIGN.md 11.5)
// NdotL을 밴드로 양자화해 그림자 경계를 뚜렷하게.
shader_type spatial;
render_mode cull_back;

uniform vec4 albedo : source_color = vec4(0.9, 0.6, 0.7, 1.0);
// 밴드 임계값 (밝음/중간/그림자)
uniform float band_hi : hint_range(0.0, 1.0) = 0.5;
uniform float band_lo : hint_range(0.0, 1.0) = 0.0;
uniform float shade_mid : hint_range(0.0, 1.0) = 0.6;
uniform float shade_dark : hint_range(0.0, 1.0) = 0.32;

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	float band;
	if (ndl > band_hi) {
		band = 1.0;
	} else if (ndl > band_lo) {
		band = shade_mid;
	} else {
		band = shade_dark;
	}
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * band;
}

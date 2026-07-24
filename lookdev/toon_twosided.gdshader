// toon.gdshader의 양면(cull_disabled) 변형 — 치마·베일처럼 급회전 시 안쪽 면이
// 보이는 얇은 천에 사용. 뒷면은 NORMAL을 뒤집어 정상 음영으로 렌더(안 그러면 검게 보임).
shader_type spatial;
render_mode cull_disabled;

uniform vec4 albedo : source_color = vec4(0.9, 0.6, 0.7, 1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform bool use_tex = false;
uniform vec4 char_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float shadow_level : hint_range(0.0, 1.0) = 0.55;
uniform vec4 shadow_tint : source_color = vec4(0.78, 0.66, 0.72, 1.0);
uniform float terminator_soft : hint_range(0.01, 0.4) = 0.18;
uniform vec4 edge_pigment : source_color = vec4(0.55, 0.45, 0.52, 1.0);
uniform float edge_strength : hint_range(0.0, 1.0) = 0.28;
uniform float curve_strength = 0.006;

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.y -= curve_strength * v.z * v.z;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	if (!FRONT_FACING) { NORMAL = -NORMAL; }  // 뒷면 음영 정상화
	vec3 base = (use_tex ? texture(albedo_tex, UV).rgb : albedo.rgb) * char_tint.rgb;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(base, edge_pigment.rgb, fres * edge_strength);
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

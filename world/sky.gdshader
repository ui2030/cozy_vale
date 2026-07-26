// 시간대 하늘: 수채 톤 그라데이션 + 시골 밤하늘 절차적 별(텍스처 없음).
// day_night.gd가 time_of_day(0~24 연속) 주입. 낮=cream→옅은블루, 노을=주황→보라, 밤=짙은청보라.
shader_type sky;

uniform float time_of_day = 12.0;

// 지평선/천정 3구간. DAY_H는 기존 배경색(0.93,0.90,0.85) 유지 → 낮 지평선 룩 불변.
const vec3 DAY_H = vec3(0.93, 0.90, 0.85);
const vec3 DAY_Z = vec3(0.84, 0.87, 0.94);   // 옅은 블루(수채 그라데이션, 낮 룩 크게 안 바꿈)
const vec3 SUN_H = vec3(0.99, 0.68, 0.42);   // 노을 주황
const vec3 SUN_Z = vec3(0.42, 0.32, 0.55);   // 노을 보라
const vec3 NIT_H = vec3(0.030, 0.040, 0.095);  // 밤 지평선(짙은 청보라; sRGB 인코딩이 어둠을 올려 실제 표시는 더 밝음)
const vec3 NIT_Z = vec3(0.012, 0.016, 0.055);  // 밤 천정

float h31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

// 셀 기반 별: scale 클수록 촘촘, thresh 클수록 희소, sz=점 크기.
float star_layer(vec3 dir, float scale, float thresh, float sz) {
	vec3 p = dir * scale;
	vec3 c = floor(p);
	float r = h31(c);
	if (r < thresh) return 0.0;  // 이 셀엔 별 없음
	vec3 off = vec3(h31(c + 1.3), h31(c + 2.7), h31(c + 4.1)) - 0.5;
	float d = length(fract(p) - 0.5 - off * 0.6);
	float s = smoothstep(sz, 0.0, d);
	float bright = 0.5 + 0.5 * h31(c + 7.7);              // 밝기 편차
	float tw = 0.82 + 0.18 * sin(TIME * 1.5 + r * 40.0);  // 은은한 반짝임(작게)
	return s * bright * tw;
}

void sky() {
	float h = time_of_day;
	float day = smoothstep(5.5, 8.0, h) - smoothstep(17.5, 20.5, h);  // 0=밤,1=낮
	float night = 1.0 - day;
	float dusk = exp(-pow((h - 18.3) / 1.7, 2.0));   // 황혼 따뜻함 피크
	float dawn = exp(-pow((h - 6.8) / 1.5, 2.0));    // 새벽 따뜻함 피크
	float warm = clamp(dusk + dawn, 0.0, 1.0);

	vec3 hor = mix(NIT_H, DAY_H, day);
	vec3 zen = mix(NIT_Z, DAY_Z, day);
	hor = mix(hor, SUN_H, warm * 0.85);
	zen = mix(zen, SUN_Z, warm * 0.55);

	vec3 dir = normalize(EYEDIR);
	// 월드 곡률이 지형을 아래로 휘어 하부 반구(dir.y<0)까지 하늘로 드러남 → 음수 고도도 하늘 대역에 포함.
	float g = smoothstep(-0.35, 0.35, dir.y);
	vec3 col = mix(hor, zen, g);
	float sky_vis = smoothstep(-0.55, -0.15, dir.y);  // 하늘이 실제 보이는 대역(그 아래는 항상 지형)

	// 은하수 띠: 한 평면 근처 미광 + 별 임계 완화(더 촘촘)
	vec3 mw_n = normalize(vec3(0.6, -0.2, 0.4));
	float mw = exp(-pow(dot(dir, mw_n) / 0.16, 2.0));

	// 별 2겹(굵은/촘촘). 시골 밤하늘 — 빽빽하게(임계 낮춤), sRGB 대비 위해 밝게.
	float st = star_layer(dir, 80.0, 0.72 - mw * 0.20, 0.13);
	st += star_layer(dir, 170.0, 0.86 - mw * 0.15, 0.09) * 0.9;
	st *= night * sky_vis;  // 해질녘 등장 / 새벽 소멸(알파 페이드)

	col += vec3(0.55, 0.60, 0.75) * mw * night * sky_vis * 0.06;  // 은하수 미광
	col += vec3(0.95, 0.96, 1.00) * st * 1.4;

	// 달: 밝은 원반 하나 + 옅은 헤일로. 보이는 대역(약간 지평선 아래)에 배치.
	vec3 moon_d = normalize(vec3(0.5, -0.10, -0.85));  // 게임 카메라(-Z 하향) 시야 안 상단
	float md = distance(dir, moon_d);
	col = mix(col, vec3(0.96, 0.96, 0.90), smoothstep(0.05, 0.035, md) * night);
	col += vec3(0.50, 0.55, 0.70) * smoothstep(0.13, 0.05, md) * night * 0.06;

	COLOR = col;
}

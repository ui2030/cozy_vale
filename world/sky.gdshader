// 시간대 하늘: 수채 톤 그라데이션 + 시골 밤하늘 절차적 별 + 플랫 툰 구름(텍스처 없음).
// day_night.gd가 time_of_day(0~24 연속) 주입. 낮=cream→옅은블루, 노을=주황→보라, 밤=짙은청보라.
// 밤하늘(별·은하수·별자리)은 천구 극축 기준으로 저속 회전. 구름은 cloud_coverage로 날씨 시스템 연동.
shader_type sky;

uniform float time_of_day = 12.0;
// 구름량 레버(날씨 시스템이 비 올 때 올림). 0=거의 맑음, 1=거의 흐림.
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.32;

// 지평선/천정 3구간. DAY_H는 기존 배경색(0.93,0.90,0.85) 유지 → 낮 지평선 룩 불변.
const vec3 DAY_H = vec3(0.93, 0.90, 0.85);
const vec3 DAY_Z = vec3(0.84, 0.87, 0.94);   // 옅은 블루(수채 그라데이션, 낮 룩 크게 안 바꿈)
// 낮 화면 상단 하늘색. 선형값이라 작아 보이지만 필믹 톤맵+sRGB를 거치면 sRGB (196,218,240) 파스텔 하늘.
// (참고로 DAY_Z를 그대로 통과시키면 (246,248,252) = 사실상 흰색이 된다 — 아래 up 주석)
const vec3 DAY_ZEN = vec3(0.36, 0.51, 0.74);
const vec3 SUN_H = vec3(0.99, 0.68, 0.42);   // 노을 주황
const vec3 SUN_Z = vec3(0.42, 0.32, 0.55);   // 노을 보라
const vec3 NIT_H = vec3(0.030, 0.040, 0.095);  // 밤 지평선(짙은 청보라; sRGB 인코딩이 어둠을 올려 실제 표시는 더 밝음)
const vec3 NIT_Z = vec3(0.012, 0.016, 0.055);  // 밤 천정

// 구름 2톤(플랫 툰: 그늘 + 빛받는 면). 밤 값은 밤하늘(NIT_*)보다 아주 조금만 밝게 —
// 일반적인 어두운 회색을 쓰면 sRGB 인코딩 때문에 밤에 구름만 허옇게 뜬다.
const vec3 CLD_DAY_L = vec3(1.00, 0.99, 0.97);
const vec3 CLD_DAY_S = vec3(0.55, 0.66, 0.85);  // 낮 지평선이 크림색이라 흰 구름은 안 보임 → 그늘은 확실히 푸른 회색
const vec3 CLD_SUN_L = vec3(1.00, 0.82, 0.58);   // 노을 주황
const vec3 CLD_SUN_S = vec3(0.86, 0.48, 0.52);   // 노을 분홍
// 밤 구름은 하늘(NIT_*)보다 어둡게 — 어두운 쪽은 sRGB 인코딩이 차이를 크게 벌려서, 조금만 밝혀도 안개처럼 허옇게 뜬다.
const vec3 CLD_NIT_L = vec3(0.034, 0.040, 0.088);  // 달빛 받는 가장자리
const vec3 CLD_NIT_S = vec3(0.016, 0.021, 0.052);  // 밤 어두운 청보라 덩어리

// 별자리(연결선 없음). vec3(접선평면 x°, y°, 밝기 0~1) — 실제 적경·적위를 중심 기준
// 탄젠트 평면으로 옮긴 값. 시야에 들어오는 하늘 띠가 좁아 배치 시 축소(SCALE)해 쓴다.
const vec3 DIPPER[7] = vec3[7](   // 북두칠성: 국자(왼쪽) + 손잡이(오른쪽 아래로)
	vec3(-9.50,  5.75, 0.69),   // Dubhe
	vec3(-11.38, 0.38, 0.46),   // Merak
	vec3(-4.47, -2.31, 0.46),   // Phecda
	vec3(-1.17,  1.03, 0.28),   // Megrez(가장 어두운 국자별)
	vec3( 4.20, -0.04, 0.69),   // Alioth
	vec3( 8.60, -1.07, 0.54),   // Mizar
	vec3(13.62, -6.69, 0.65)    // Alkaid
);
const vec3 CASSIO[5] = vec3[5](   // 카시오페이아: W 지그재그
	vec3(-6.51, -0.85, 0.50),   // Caph
	vec3(-2.69, -3.46, 0.54),   // Schedar
	vec3(-0.40,  0.72, 0.54),   // Gamma
	vec3( 3.20,  0.24, 0.35),   // Ruchbah
	vec3( 6.03,  3.67, 0.24)    // Segin
);
const vec3 ORION[7] = vec3[7](    // 오리온: 어깨 둘 + 삼태성 + 발 둘
	vec3( 4.75,  7.41, 1.00),   // Betelgeuse
	vec3(-2.71,  6.35, 0.77),   // Bellatrix
	vec3(-1.00, -0.30, 0.54),   // Mintaka(삼태성)
	vec3( 0.06, -1.20, 0.73),   // Alnilam
	vec3( 1.19, -1.94, 0.69),   // Alnitak
	vec3( 2.90, -9.67, 0.58),   // Saiph
	vec3(-5.32, -8.20, 1.00)    // Rigel
);
// 별자리 중심 방향(게임 카메라가 -Z 북향 고정 → 시야에 잡히는 좁은 띠 안에 배치)과 축소율.
// (광장 기준 화면에서 시계탑 회관·달을 피해 배치 — 왼쪽 위 북두칠성, 왼쪽 아래 카시오페이아, 오른쪽 오리온)
const vec3 DIPPER_C = vec3(-0.365, -0.225, -0.903);
const vec3 CASSIO_C = vec3(-0.276, -0.345, -0.897);
const vec3 ORION_C  = vec3( 0.355, -0.262, -0.897);
const vec3 POLE = vec3(0.0, 0.750, -0.661);  // 천구 극축(북쪽 위) — 밤하늘 회전 중심

float h31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float h21(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
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

// 로드리게스 회전: 축 k(정규화) 둘레로 v를 a만큼.
vec3 rot_axis(vec3 v, vec3 k, float a) {
	float c = cos(a);
	return v * c + cross(k, v) * sin(a) + k * dot(k, v) * (1.0 - c);
}

// 별자리 별 하나. s=(x°, y°, 밝기). 주변 별보다 크고 밝게 + 옅은 헤일로.
float cstar(vec3 dir, vec3 ctr, vec3 rt, vec3 up, vec3 s, float sc) {
	float k = 0.017453 * sc;  // 도 → 라디안(축소 적용)
	vec3 p = normalize(ctr + rt * (s.x * k) + up * (s.y * k));
	float d = distance(dir, p);  // 작은 각에서 현길이 ≈ 각거리
	float sz = 0.003 + 0.004 * s.z;
	return smoothstep(sz, sz * 0.2, d) * (0.5 + 0.6 * s.z)
		 + smoothstep(sz * 2.5, sz, d) * 0.10 * s.z;
}

float constellation(vec3 dir, vec3 ctr, float sc, int which) {
	vec3 rt = normalize(cross(ctr, vec3(0.0, 1.0, 0.0)));  // 화면 오른쪽(-Z 전방 우수계)
	vec3 up = cross(rt, ctr);
	float v = 0.0;
	if (which == 0) { for (int i = 0; i < 7; i++) v += cstar(dir, ctr, rt, up, DIPPER[i], sc); }
	else if (which == 1) { for (int i = 0; i < 5; i++) v += cstar(dir, ctr, rt, up, CASSIO[i], sc); }
	else { for (int i = 0; i < 7; i++) v += cstar(dir, ctr, rt, up, ORION[i], sc); }
	return v;
}

// ── 구름 노이즈: 밸류 fbm(뭉게진 몸통) × 워리(둥근 덩어리 경계) ────────────
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x),
			   mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s / 0.9375;  // 0~1 정규화
}

float worley(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d = 1.5;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 c = g + vec2(h21(i + g), h21(i + g + 7.7));
			d = min(d, length(c - f));
		}
	}
	return d;
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

	// 낮 하늘 상단이 백지로 뜨던 원인 두 가지를 여기서 한꺼번에 뺀다.
	//  ① 추종 카메라가 ~29° 내려보고 세로 fov가 48이라 화면 최상단조차 dir.y ≈ -0.09다 →
	//     위 g(천정 도달 = dir.y 0.35)는 화면에서 0.31까지밖에 안 올라, 천정색이 사실상 안 쓰인다.
	//  ② 그 DAY_Z(0.84,0.87,0.94)마저 선형값이라 필믹 톤맵·sRGB를 거치면 (246,248,252) = 흰색.
	// → 실제로 화면에 잡히는 대역(-0.52 지평선 ~ -0.06 프레임 위)에만 낮 전용 하늘색을 얹는다.
	// 노을·밤은 승인된 룩이라 warm(황혼/새벽 피크)·day로 게이트 — 18시 계수 0.03, 21시 0 = 값 불변.
	col = mix(col, DAY_ZEN, smoothstep(-0.52, -0.06, dir.y) * day * (1.0 - warm));

	// 라디언스 큐브맵엔 별·구름 같은 고주파를 넣지 않는다(에일리어싱 + 낭비). 그라데이션만.
	if (!AT_CUBEMAP_PASS) {
		float cov = clamp(cloud_coverage, 0.0, 1.0);  // 날씨 시스템이 범위 밖 값을 넣어도 안전하게
		float ca = 0.0;          // 구름 알파
		vec3 cloud_col = col;
		if (cov > 0.001) {
			// 구름: 방위각·고도 직교 좌표(dir.y가 음수라 dome 투영은 특이점 발생 → 각도 좌표 사용).
			vec2 uv = vec2(atan(dir.x, -dir.z) * 3.2, dir.y * 5.6) + vec2(TIME * 0.004, 0.0);
			// 원 노이즈는 0.40~0.78에 몰려 있어(표준편차 ~0.1) 그대로 문턱을 걸면 구름이 거의 안 뜬다 → 0~1로 펴고 자름.
			float n = clamp((fbm(uv) * 0.65 + (1.0 - worley(uv * 1.3)) * 0.35 - 0.40) * 2.6, 0.0, 1.0);
			float thr = mix(1.05, 0.10, cov);   // coverage 0=거의 맑음, 1=거의 흐림
			// 구름 안쪽 진하기(0=가장자리,1=심). 문턱 기준 정규화라 coverage를 바꿔도 2톤 비율이 유지됨.
			float t = (n - thr) / max(0.05, 1.0 - thr);
			ca = smoothstep(0.0, 0.05, t) * sky_vis;   // 플랫 툰: 좁은 경계
			float core = smoothstep(0.60, 0.70, t);    // 심만 밝은 2번째 톤(대부분은 그늘 톤)
			vec3 cl = mix(CLD_NIT_L, CLD_DAY_L, day);
			vec3 csh = mix(CLD_NIT_S, CLD_DAY_S, day);
			cl = mix(cl, CLD_SUN_L, warm * 0.85);
			csh = mix(csh, CLD_SUN_S, warm * 0.85);
			cloud_col = mix(csh, cl, core);
		}

		// 낮엔 별·달이 안 보이므로 통째로 건너뛴다(time_of_day는 uniform이라 분기가 갈라지지 않음).
		if (night > 0.001) {
			// 밤하늘 저속 회전: 극축 둘레로. 22시 기준 각도 0(별자리 배치 기준 시각).
			float hn = h < 12.0 ? h + 24.0 : h;      // 밤을 18~29시로 연속화(자정 점프 방지)
			vec3 rd = rot_axis(dir, normalize(POLE), (hn - 22.0) * 0.05);  // 시간당 ~2.9°

			// 은하수 띠: 한 평면 근처 미광 + 별 임계 완화(더 촘촘)
			vec3 mw_n = normalize(vec3(0.6, -0.2, 0.4));
			float mw = exp(-pow(dot(rd, mw_n) / 0.16, 2.0));

			// 별 2겹(굵은/촘촘). 시골 밤하늘 — 빽빽하게(임계 낮춤), sRGB 대비 위해 밝게.
			float st = star_layer(rd, 80.0, 0.72 - mw * 0.20, 0.13);
			st += star_layer(rd, 170.0, 0.86 - mw * 0.15, 0.09) * 0.9;
			// 별자리: 주변 별보다 크고 밝게(선은 긋지 않음)
			float cs = constellation(rd, normalize(DIPPER_C), 0.55, 0);
			cs += constellation(rd, normalize(CASSIO_C), 0.60, 1);
			cs += constellation(rd, normalize(ORION_C), 0.45, 2);

			float nv = night * sky_vis;   // 해질녘 등장 / 새벽 소멸(알파 페이드)
			float occ = 1.0 - ca * 0.95;  // 구름이 별·은하수를 가림
			col += vec3(0.55, 0.60, 0.75) * mw * nv * 0.06 * occ;  // 은하수 미광
			col += vec3(0.95, 0.96, 1.00) * st * 1.4 * nv * occ;
			col += vec3(0.97, 0.97, 1.00) * cs * nv * occ;

			// 달: 밝은 원반 하나 + 옅은 헤일로. 보이는 대역(약간 지평선 아래)에 배치.
			vec3 moon_d = normalize(vec3(0.5, -0.10, -0.85));  // 게임 카메라(-Z 하향) 시야 안 상단
			float md = distance(dir, moon_d);
			col = mix(col, vec3(0.96, 0.96, 0.90), smoothstep(0.05, 0.035, md) * night * occ);
			col += vec3(0.50, 0.55, 0.70) * smoothstep(0.13, 0.05, md) * night * 0.06 * occ;
		}

		col = mix(col, cloud_col, ca);
	}

	COLOR = col;
}

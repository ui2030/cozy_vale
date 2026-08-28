// 바람의 지휘봉풍 툰 물: 절차적 value noise 하이라이트 패치가 흐르는 플랫 2단 톤.
// 텍스처 없음(셰이더 내 노이즈). 곡률 vertex는 toon.gdshader와 동일 — 정적 지형과 어긋나지 않게.
shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.50, 0.72, 0.85, 1.0);       // C_WATER(마을 팔레트)
uniform vec4 highlight_color : source_color = vec4(0.74, 0.89, 0.97, 1.0);  // 밝은 물감 패치
// 노을·새벽 수면(하늘빛 반사). 청록 albedo × 주황 태양광 = 올리브 — 곱하기 전에 albedo를
// 하늘 쪽으로 옮겨야 한다. B>G인 연보라빛 분홍인 이유: 노을 조명이 ≈(R0.67 G0.49 B0.37)이라
// B를 깎으므로 미리 되갚아야 화면에서 장밋빛으로 앉는다(주황을 그대로 넣으면 붉은 찰흙, 실측).
// 밝기를 옛 값의 0.72배로 눌러 둔다. 옛 값(휘도 0.71/0.92)은 낮 쌍과 같은 밝기라 노을 조명을
// 그대로 받아 강이 흙둑(154)·잔디(183)와 같은 값(165)이 됐다 = **강이 사라졌다**
// (실측 audit2_0809/bridgetop_h18, beach_shore_h18은 바다 165 vs 모래 180). 물은 하늘을 비추는
// 어두운 면이어야 지면에서 떨어져 나온다 — 값을 내리고 B를 R까지 올려 색상까지 갈라 놓는다.
// 0.48배까지 내려 봤더니 강이 진흙 도랑(85)이 됐다 — 0.72가 "지면과 분리되되 물로 읽히는" 선.
// 두 색의 비(1.41)는 낮 쌍(1.35)과 맞춘다: 2단 톤의 단차가 시간대마다 달라지면 물성이 흔들린다.
uniform vec4 warm_color : source_color = vec4(0.62, 0.46, 0.62, 1.0);
uniform vec4 warm_highlight : source_color = vec4(0.80, 0.68, 0.76, 1.0);
uniform float warm_glow = 0.12;     // 반사광 가산(태양이 지평선이라 수면 N·L≈0 = 디퓨즈만으론 어둡고 탁하다).
                                    // 올리면 하늘처럼 밝아지지만 0.3부터는 수평선이 하늘에 붙는다(실측).
                                    // 이 항은 조명과 무관한 평탄 가산이라 값 분리를 정확히 갉아먹는다 —
                                    // 어두워진 물 위에서 0.18은 다시 지면 값으로 끌어올린다(0.12가 상한).
uniform float noise_scale = 0.6;    // 패치 크기(작을수록 큰 패치)
uniform float flow_speed = 0.06;    // 흐름 속도
uniform float coverage : hint_range(0.0, 1.0) = 0.60;  // 하이라이트 임계(클수록 패치 좁음)
uniform float curve_strength = 0.006;  // toon.gdshader와 동일 월드 곡률
// 곡률이 멈추는 뷰 깊이(m). 기본값은 사실상 무한 = 연못·강은 지금까지와 완전히 같다.
// 바다만 유한값을 넣는다: 툰 곡률은 원경을 아래로 말아 넣어 수면을 크레스트에서 끊으므로,
// 넓은 물은 화면 중간의 얇은 띠로 끝난다. 이 깊이 밖을 평평하게 두면 수평선이 선다.
uniform float curve_cap = 1.0e4;   // 기본 10km = 어떤 컷에서도 캡에 닿지 않는다(연못·강 불변)
// ── 밀려오는 파도선 (해변 전용 — foam_gap 0이면 분기 자체가 꺼진다) ──
uniform float foam_gap = 0.0;       // 파도선 간격(m). 0 = 끄기
uniform float foam_z = 0.0;         // 위상 기준 월드 z = 물가선(여기서 파도가 부서진다)
uniform float foam_duty : hint_range(0.0, 0.5) = 0.13;  // 간격 중 흰 선이 차지하는 비율
uniform float foam_speed = 0.045;   // 물가 쪽(+z)으로 밀려오는 속도(간격/초)
uniform vec4 foam_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// ── 원경 대기 띠 (해변 전용 — haze 0이면 분기 자체가 꺼진다) ──
// 재감사(2026-08-09) "수평선이 칼직선". 곡률 캡(curve_cap)이 원경을 평평하게 세워 수평선을
// 만들어 주지만, 그 대가로 판 끝이 자로 그은 경계로 하늘과 맞붙는다 — 실측 sea_before_h12에서
// 경계 위 하늘 (222,231,242) / 아래 물 (168,219,243), R만 54단차라 칼금으로 읽힌다.
// 판 끝으로 갈수록 물색을 하늘 쪽으로 녹여 그 단차를 0에 가깝게 만든다(대기 원근).
// 이 띠는 **조명을 안 받는다**(ALBEDO를 비우고 EMISSION으로만 그린다). 대기는 태양을 반사하는
// 면이 아니라 하늘빛을 산란하는 것이라서다. 처음엔 albedo로 얹어 봤고 정오는 딱 맞았지만
// (실측: 하늘 222,231,242 / 수평선 물 221,230,243), 노을엔 **원리적으로 못 맞춘다** —
// 18시 태양이 주황(B 0.42×0.95)이라 조명을 받는 면은 albedo를 1.0까지 올려도 B가 178에서
// 막히는데 하늘은 218이다. 무광원으로 빼면 시각과 무관하게 하늘값을 그대로 쓸 수 있다.
uniform float haze : hint_range(0.0, 1.0) = 0.0;
// 세 값 다 **화면 실측 역산**이다(lookdev/shots/water/sea_cal_h*.png, 1차 근사 후 1회 보정).
// 시간대 셋으로 가른 건 sky.gdshader의 DAY_H/SUN_H/NIT_H와 같은 규약이다 — 수평선에서 맞춰야
// 하는 상대가 바로 그 세 값이라서다.
//   정오 하늘 (222,231,242) / 노을 (251,236,218) / 밤 21시 (108,101,122)
uniform vec4 haze_color : source_color = vec4(0.760, 0.813, 0.875, 1.0);  // 낮 수평선 하늘
uniform vec4 haze_warm : source_color = vec4(0.953, 0.863, 0.760, 1.0);   // 노을 수평선 하늘
// 밤값이 유난히 푸른 건 위 합성 순서 때문이다: 21시에도 warm이 0.08 남아 haze_warm(크림)이
// 6.8% 섞이므로 R·G는 거기서 온다 — 밤 상수는 그 나머지만 채운다(하늘이 NIT_H에 SUN_H를
// 같은 비율로 얹는 것과 같은 구조). 이 상수만 따로 보고 "밤 하늘색"으로 읽으면 안 된다.
uniform vec4 haze_night : source_color = vec4(0.187, 0.195, 0.324, 1.0);  // 밤 수평선 하늘
global uniform float time_of_day;   // day_night.gd가 매 프레임 주입(0~24 연속). 하늘과 같은 단일 출처.

varying vec2 world_xz;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

// value noise (bilinear + smoothstep)
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;  // 월드좌표로 연못·강 패치 크기 통일
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.y -= curve_strength * min(v.z * v.z, curve_cap * curve_cap);
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	vec2 t = vec2(TIME * flow_speed, TIME * flow_speed * 0.7);
	float n = vnoise(world_xz * noise_scale + t);
	n = n * 0.65 + vnoise(world_xz * noise_scale * 2.0 - t * 1.3) * 0.35;
	float hl = step(coverage, n);  // 플랫 2단 톤(그라데이션 없음)
	// 따뜻함 가중: sky.gdshader의 dusk/dawn 가우시안과 같은 식 — 시간대 if 분기 없음.
	// 정오엔 1e-5 수준(8비트 1/255=0.004 훨씬 아래) = 낮 룩 불변. 밤(21시 0.08)도 거의 청색 유지.
	float warm = clamp(exp(-pow((time_of_day - 18.3) / 1.7, 2.0))
					 + exp(-pow((time_of_day - 6.8) / 1.5, 2.0)), 0.0, 1.0);
	vec3 col = mix(mix(base_color.rgb, highlight_color.rgb, hl),
				   mix(warm_color.rgb, warm_highlight.rgb, hl), warm * 0.9);
	// 파도선: 물가선을 위상 0으로 삼아 일정 간격으로 반복하고 물가 쪽으로 흐른다.
	// 같은 value noise로 흔들어 자로 그은 직선이 아니라 굽이치는 물마루가 된다.
	// 원경(캡 밖)에선 간격이 픽셀 이하로 압축돼 모아레가 되므로 그 전에 녹여 없앤다.
	if (foam_gap > 0.0) {
		float wob = (vnoise(vec2(world_xz.x * 0.16, TIME * 0.06)) - 0.5) * foam_gap * 0.5;
		float ph = fract((world_xz.y - foam_z + wob) / foam_gap - TIME * foam_speed);
		// 0.85·cap(=34)까지 온전히, 1.3·cap(=52)에서 완전히 녹는다 — 도착 지점에서 물가선의
		// 뷰 깊이가 이미 23이라 이보다 일찍 시작하면 파도선이 물가에서부터 유령이 된다(실측).
		float near = 1.0 - smoothstep(0.85, 1.3, -VERTEX.z / curve_cap);
		// 노을엔 흰 선이 물 자체의 웜 하이라이트에 묻힌다 — 절반만 물들여 한 단 더 밝게 남긴다.
		col = mix(col, mix(foam_color.rgb, warm_highlight.rgb, warm * 0.5), step(ph, foam_duty) * near);
	}
	// 파도선 **뒤에** 건다 — 원경 파도선까지 같이 녹아야 한다(멀리서 흰 선이 또렷하면
	// 대기 띠가 무색해지고, 간격이 픽셀 이하로 압축돼 모아레가 남는다).
	// 0.70~1.35·cap(=28~54): 물가선 뷰 깊이가 최대 36이라 0.70(28)보다 이르게 시작하면
	// 걸어다니는 자리 앞바다까지 뿌옇게 뜬다(파도선 페이드 0.85~1.3과 같은 근거·한 단 넓게).
	// 밤엔 day로 띠를 통째로 껐었다(무광원이라 밤에 띠만 발광할까 봐). 되돌렸다 —
	// 밤 수평선이야말로 단차가 제일 컸다(실측 21시: 하늘 108,101,122 vs 물 38,61,92).
	// 밤 색을 따로 주는 쪽이 맞다.
	float hz = 0.0;
	vec3 hcol = vec3(0.0);
	if (haze > 0.0) {
		hz = smoothstep(0.70, 1.35, -VERTEX.z / curve_cap) * haze;
		// 합성 순서까지 sky.gdshader의 지평선(hor)과 **글자 그대로** 같다: 밤↔낮을 day로 섞고
		// 그 위에 노을을 warm*0.85로 덮는다. 순서를 바꿔 봤더니(밤↔노을을 day로 섞기) 새벽 7시에
		// 하늘은 이미 주황인데 띠만 35% 밤색이라 20레벨 어긋났다(실측 sea_after_h7).
		float day = clamp(smoothstep(5.5, 8.0, time_of_day) - smoothstep(17.5, 20.5, time_of_day), 0.0, 1.0);
		hcol = mix(mix(haze_night.rgb, haze_color.rgb, day), haze_warm.rgb, warm * 0.85);
	}
	ALBEDO = col * (1.0 - hz);
	EMISSION = col * warm * warm_glow * (1.0 - hz) + hcol * hz;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

# 외부 에셋 출처와 라이선스

## 저장소에 포함 (CC0)

### `assets/tinytreats/` — Tiny Treats (Isa Lousberg)
- 출처: https://tinytreats.itch.io/
- 라이선스: **CC0 1.0** — 개인·교육·상업 전부 자유, 재배포 자유, 크레딧 선택
- 포함 세트(무료판): Pretty Park, Charming Kitchen, Baked Goods, Bubbly Bathroom, Pleasant Picnic
- 형식: `Assets/gltf`(권장) · `Assets/fbx` · `Assets/obj` · `Assets/Textures`
- 크레딧(의무 아님): Isa Lousberg — www.isalousberg.com

---

## 저장소에 **미포함** — 각자 받아야 함 (`.gitignore` 처리)

아래는 **재배포 금지** 조건이라 공개 저장소에 올릴 수 없다. 클론 후 직접 받아 `assets/vendor/` 에 풀어야 한다.

### `assets/vendor/plumberry-plains-props-vol-1/`, `.../-tools-vol-1/`
- 출처: https://chibipup.itch.io/ (Plumberry Plains Town Props / Tools Vol. 1)
- 라이선스(TERMS.md 요약):
  - 개인·**상업** 프로젝트 사용 가능
  - **재배포 금지** — "may not resell, redistribute, sublicense, or share the raw asset files ... in any marketplace or **repository**"
  - 생성형 AI 학습 금지, NFT 금지
  - 크레딧 선택
- 형식: `props/<name>/<name>.glb`(Godot 네이티브) · `.fbx` · `.obj`
- 규약: 원점 = 바닥 중심, 타일 1×1 m, 단위 미터, Y-up, 프롭당 머티리얼 1개

### `assets/vendor/Sprout Lands - UI Pack - Basic pack/`
- 출처: https://cupnooble.itch.io/sprout-lands-asset-pack (Cup Nooble)
- 라이선스(read_me.txt 요약):
  - 수정 가능
  - **재배포·재판매 금지**
  - **비상업 프로젝트 전용** — 상업 사용하려면 **Premium 구매 필요**
  - NFT 금지
- ⚠️ **출시 전 반드시 Premium 구매로 교체하거나 UI를 자체 제작해야 한다.** 현재는 룩 평가 목적으로만 적용.
- 형식: PNG 스프라이트시트 + 픽셀 폰트(`pixelFont-7-8x14-sproutLands.ttf`)
- ⚠️ 픽셀 폰트에 한글 글리프가 없을 가능성이 높다 → 프레임·아이콘만 쓰고 **본문 폰트는 기존 것 유지**.

**적용 방식 (ui/hud.gd)**: 시트를 Godot 임포트가 아니라 `FileAccess` + `Image.load_png_from_buffer`로
런타임 로드한다(`*.import`도 gitignore라 임포트 경로를 못 쓴다). 파일이 없으면 조용히 옛 어두운
패널로 폴백하므로 클론에서도 그대로 돌아간다. 좌표는 시트 알파 경계 실측:
크림 패널 `(11,57,26,30)` · 버튼 `(11,105,26,30)` · 눌림 `(107,105,26,30)`.

⚠️ **export 함정**: 임포트 리소스가 아니라서 **내보내기 시 PNG가 패키지에 안 담긴다**.
지금은 평가용이라 문제없지만(에디터/소스 실행만), Premium으로 교체해 실제로 출시할 땐
① 정상 임포트 경로로 옮기거나 ② export preset의 "Filters to export non-resource files"에
PNG를 추가해야 한다. 안 하면 **빌드에서만 UI가 옛 패널로 폴백한다**(개발 중엔 안 보이는 버그).

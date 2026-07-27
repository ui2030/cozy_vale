# Credits

Cozy Vale에 포함된 서드파티 에셋의 출처와 라이선스.
전부 **CC0 1.0 (Public Domain Dedication)** — 상업적 사용·수정·재배포 자유, 저작자 표시 의무 없음.
아래 표기는 의무가 아니라 예의로 남긴다.

모든 파일은 원본과 **바이트 단위로 동일**하다(재인코딩 없음, 파일명만 용도에 맞게 변경).
확인 방법: 아래 출처에서 원본을 받아 `assets/audio/` 파일과 MD5를 비교.

---

## 효과음 — `assets/audio/sfx/`

Kenney (Kenney Vleugels, kenney.nl) — CC0 1.0.

| 게임 내 파일 | 원본 팩 | 원본 파일명 |
|---|---|---|
| `cast.ogg` | [Interface Sounds](https://kenney.nl/assets/interface-sounds) | `Audio/drop_003.ogg` |
| `coin.ogg` | [RPG Audio](https://kenney.nl/assets/rpg-audio) | `Audio/handleCoins.ogg` |
| `deposit.ogg` | [RPG Audio](https://kenney.nl/assets/rpg-audio) | `Audio/dropLeather.ogg` |
| `fish_fail.ogg` | [Interface Sounds](https://kenney.nl/assets/interface-sounds) | `Audio/back_002.ogg` |
| `fish_success.ogg` | [Interface Sounds](https://kenney.nl/assets/interface-sounds) | `Audio/confirmation_002.ogg` |
| `harvest.ogg` | [Interface Sounds](https://kenney.nl/assets/interface-sounds) | `Audio/confirmation_001.ogg` |
| `hoe.ogg` | [Impact Sounds](https://kenney.nl/assets/impact-sounds) | `Audio/impactMining_000.ogg` |
| `pickup.ogg` | [Interface Sounds](https://kenney.nl/assets/interface-sounds) | `Audio/select_001.ogg` |
| `plant.ogg` | [RPG Audio](https://kenney.nl/assets/rpg-audio) | `Audio/cloth1.ogg` |
| `sleep.ogg` | [Interface Sounds](https://kenney.nl/assets/interface-sounds) | `Audio/minimize_001.ogg` |
| `step.ogg` | [Impact Sounds](https://kenney.nl/assets/impact-sounds) | `Audio/footstep_grass_000.ogg` |
| `talk.ogg` | [Interface Sounds](https://kenney.nl/assets/interface-sounds) | `Audio/bong_001.ogg` |
| `ui_close.ogg` | [Interface Sounds](https://kenney.nl/assets/interface-sounds) | `Audio/close_001.ogg` |
| `ui_open.ogg` | [Interface Sounds](https://kenney.nl/assets/interface-sounds) | `Audio/open_001.ogg` |
| `water.ogg` | [Interface Sounds](https://kenney.nl/assets/interface-sounds) | `Audio/drop_001.ogg` |

## 환경음 — `assets/audio/ambience/`

Kenney에는 자연 환경음 팩이 없어 OpenGameArt.org의 CC0 음원을 사용했다(라이선스 등급은 동일).

| 게임 내 파일 | 작가 | 출처 | 원본 파일명 |
|---|---|---|---|
| `bird_day.ogg` | isaiah658 | [Ambient Bird Sounds](https://opengameart.org/content/ambient-bird-sounds) | `birds-isaiah658.ogg` |
| `cricket_night.mp3` | Wolfgang_ (rec. Ted Kerr) | [Crickets Ambient Noise - loopable](https://opengameart.org/content/crickets-ambient-noise-loopable) | `crickets.mp3` |
| `water_loop.ogg` | rubberduck | [30 CC0 SFX loops](https://opengameart.org/content/30-cc0-sfx-loops) | `water_flowing.ogg` |

## 실내 가구·구조물 — `assets/furniture/`

Kenney (Kenney Vleugels, kenney.nl) — [Furniture Kit 2.0](https://kenney.nl/assets/furniture-kit), CC0 1.0.
원본 배포판의 `Models/GLTF format/` 안에서 **실제로 쓰는 조각만** 골라 복사했다(파일명·바이트 무변경).
게임은 Godot 임포트 파이프라인이 아니라 런타임 `GLTFDocument` 로드를 쓴다(`world/interior.gd`).

| 게임 내 파일 | 용도 |
|---|---|
| `floorFull.glb` | 실내 바닥 타일 |
| `wall.glb` | 벽 |
| `wallWindow.glb` | 창문 벽 |
| `wallDoorway.glb` | 문틀 벽 (실내 출구) |
| `bedDouble.glb` | 부부 침대 (취침 트리거) |
| `sideTable.glb` | 침대 협탁 |
| `lampRoundTable.glb` | 협탁 위 램프 |
| `lampRoundFloor.glb` | 스탠드 조명 |
| `table.glb` | 식탁 |
| `chair.glb` | 식탁 의자 ×2 |
| `bookcaseClosedDoors.glb` | 책장 |
| `rugRectangle.glb` | 러그 |
| `pottedPlant.glb` | 화분 |
| `kitchenStove.glb` | 부엌 — 레인지 |
| `kitchenSink.glb` | 부엌 — 싱크대 |
| `kitchenFridge.glb` | 부엌 — 냉장고 |

# 뱃지 일러스트 생성 프롬프트 (19개)

Midjourney / ChatGPT(이미지) / 나노바나나 등 어디든 쓸 수 있게 영어로 적음. `[STYLE]` 자리에 아래 공통 스타일 문장을 그대로 붙인다.

## 파일 규격 (코드와 맞추는 부분)

- 정사각 **1024×1024**, 배경 투명 PNG (투명이 안 되면 **순검정 #000000** 배경으로 뽑고 그대로 씀 — 앱이 다크 기준)
- 뱃지가 캔버스의 약 80%를 채우고 정중앙. 그림자·바닥·주변 장식 없음
- **획득(컬러) 버전만** 필요. 미획득 회색 상태는 코드가 흑백·반투명으로 처리
- 파일명은 `Badge.rawValue`와 동일하게 → `badge_firstRun.png`, `badge_fiveK.png` … (아래 표) — `Assets.xcassets`에 이 이름으로 넣으면 코드 한 줄로 교체 가능
- 같은 세트로 보이게 하는 게 제일 중요. Midjourney면 첫 장(첫 러닝)을 뽑은 뒤 그 이미지 URL을 `--sref`로 나머지 18장에 전부 붙일 것. ChatGPT/나노바나나면 첫 장을 첨부하고 "same style, same lighting, same line weight"로 이어서 뽑기

## 공통 스타일 `[STYLE]`

```
flat vector sports achievement badge, circular medal shape with a thick outer ring, bold simplified shapes, clean geometric line work, subtle inner gradient only (no photorealism, no 3D render, no glossy bevel), high contrast, centered composition, isolated on transparent background, no shadow, no extra text, no watermark, style of Nike Run Club trophies
```

## 네거티브 (Midjourney `--no`, SD negative)

```
text, letters, watermark, photo, 3d, bevel, glossy, shadow, background scene, multiple badges, frame, border, blurry
```

## 카테고리 색 (세트 안에서 계열이 이어지게)

| 카테고리 | 색 계열 | 상징 |
|---|---|---|
| 거리 (한 번에) | 노랑 → 주황 → 코랄 → 은 → 금 (레벨 컬러 순서) | 체크 깃발·메달 |
| 누적 | 초록 → 청록 → 파랑 → 남색 → 보라 | 도로·지도 경로선 |
| 연속 | 주황 → 빨강 → 진홍 | 불꽃 |
| 횟수 | 민트 → 틸 → 짙은 틸 | 반복 화살표·루프 |
| 시간대 | 새벽 핑크·보라 / 밤 남색·별 | 해·달 |

숫자는 뱃지 안에 **크게 한 번만**. 생성기가 글자를 자주 틀리니 뽑은 뒤 반드시 확인 — 계속 틀리면 숫자 없이 뽑고 숫자는 코드로 얹어도 됨 (Claude에게 말하면 처리).

## 19개 프롬프트

### 거리 (한 번에 달린 거리)

| 파일명 | 뱃지 | 프롬프트 |
|---|---|---|
| `badge_firstRun` | 첫 러닝 | `[STYLE], a single running shoe leaving a short motion trail, warm golden yellow and white palette, a small sparkle above the shoe, no numbers --ar 1:1` |
| `badge_fiveK` | 5K | `[STYLE], large bold numeral "5K" in the center, a checkered finish flag behind it, bright yellow ring with dark navy center --ar 1:1` |
| `badge_tenK` | 10K | `[STYLE], large bold numeral "10K" in the center, two checkered flags crossed behind it, vivid orange ring with dark navy center --ar 1:1` |
| `badge_fifteenK` | 15K | `[STYLE], large bold numeral "15K" in the center, a checkered flag and a winding road behind it, coral red ring with dark navy center --ar 1:1` |
| `badge_halfMarathon` | 하프 마라톤 | `[STYLE], a silver medal on a short ribbon, the numeral "21.1" engraved in the medal, brushed silver and charcoal palette, laurel leaves on both sides --ar 1:1` |
| `badge_marathon` | 풀 마라톤 | `[STYLE], a gold medal on a ribbon, the numeral "42.2" engraved in the medal, rich gold and deep navy palette, full laurel wreath around the ring, slightly larger and more ornate than the other medals --ar 1:1` |

### 누적 거리

| 파일명 | 뱃지 | 프롬프트 |
|---|---|---|
| `badge_total50km` | 50km | `[STYLE], a straight road with center dashes seen from above, bold numeral "50" on the road, fresh green ring --ar 1:1` |
| `badge_total100km` | 100km | `[STYLE], a gently curving road seen from above, bold numeral "100" on the road, teal ring --ar 1:1` |
| `badge_total250km` | 250km | `[STYLE], a winding road with two curves seen from above, bold numeral "250" on the road, sky blue ring --ar 1:1` |
| `badge_total500km` | 500km | `[STYLE], a road forming a loop like a route on a map, bold numeral "500" in the loop, deep blue ring --ar 1:1` |
| `badge_total1000km` | 1,000km | `[STYLE], a road circling the whole badge like a planet orbit with a small globe in the center, bold numeral "1000" across the globe, royal purple ring with gold accents --ar 1:1` |

### 연속 일수

| 파일명 | 뱃지 | 프롬프트 |
|---|---|---|
| `badge_streak3` | 3일 연속 | `[STYLE], a single small flame, bold numeral "3" inside the flame, warm orange ring --ar 1:1` |
| `badge_streak7` | 7일 연속 | `[STYLE], a medium flame with two tongues, bold numeral "7" inside the flame, orange to red ring --ar 1:1` |
| `badge_streak30` | 30일 연속 | `[STYLE], a large roaring flame filling the badge, bold numeral "30" inside the flame, crimson red ring with a thin gold inner line --ar 1:1` |

### 러닝 횟수

| 파일명 | 뱃지 | 프롬프트 |
|---|---|---|
| `badge_runs10` | 10회 | `[STYLE], two curved arrows forming a repeat loop, bold numeral "10" in the center of the loop, mint green ring --ar 1:1` |
| `badge_runs50` | 50회 | `[STYLE], two curved arrows forming a repeat loop with a second thinner loop behind it, bold numeral "50" in the center, teal ring --ar 1:1` |
| `badge_runs100` | 100회 | `[STYLE], three stacked repeat-loop arrows suggesting momentum, bold numeral "100" in the center, deep teal ring with a gold inner line --ar 1:1` |

### 시간대

| 파일명 | 뱃지 | 프롬프트 |
|---|---|---|
| `badge_earlyBird` | 얼리버드 | `[STYLE], a rising sun half above a flat horizon line with three short rays, a tiny bird silhouette flying in front of the sun, dawn palette of soft pink, peach and lavender, no numbers --ar 1:1` |
| `badge_nightRunner` | 나이트 러너 | `[STYLE], a crescent moon with three small stars, a tiny running figure silhouette beneath the moon, night palette of deep navy and indigo with pale yellow moon, no numbers --ar 1:1` |

## Midjourney 실제 입력 예 (첫 러닝)

```
flat vector sports achievement badge, circular medal shape with a thick outer ring, bold simplified shapes, clean geometric line work, subtle inner gradient only (no photorealism, no 3D render, no glossy bevel), high contrast, centered composition, isolated on transparent background, no shadow, no extra text, no watermark, style of Nike Run Club trophies, a single running shoe leaving a short motion trail, warm golden yellow and white palette, a small sparkle above the shoe, no numbers --ar 1:1 --style raw --no text, letters, watermark, photo, 3d, bevel, glossy, shadow, background scene, multiple badges, frame, border, blurry
```

두 번째부터: 같은 문장 + `--sref <첫 러닝 이미지 URL>`.

## 뽑은 뒤 체크

- [ ] 19장이 한 세트로 보이는가 (링 두께·선 굵기·밝기)
- [ ] 숫자 오타 없음 (5K·10K·15K·21.1·42.2·50·100·250·500·1000·3·7·30·10·50·100)
- [ ] 배경 투명 또는 #000000 — 회색 배경이 남아 있으면 remove.bg 등으로 제거
- [ ] 흑백으로 바꿔도 형태가 구분되는가 (미획득 상태용)
- [ ] `Assets.xcassets`에 `badge_<rawValue>` 이름으로 넣고 Claude에게 "뱃지 이미지 연결해줘"

# RunCanvas 디자인 시스템

코드에서 뽑아 정리한 현재 규칙. 새 화면을 만들 때 이 문서를 먼저 보고, 규칙을 바꾸면 코드와 이 문서를 같이 고친다.
원본 토큰은 `RunCanvas/Components/Theme.swift`, 컴포넌트는 `RunCanvas/Components/`.

## 브랜드

**RunCanvas** — 러닝 기록 앱. 태그라인 "Every Run, A Canvas." 달린 기록(거리·시간·페이스·경로)을 캔버스 위에 스티커처럼 얹어 꾸미고 공유한다(런꾸). 레벨은 NRC처럼 누적 거리 색으로 오른다.

한 줄 정체성: **흑백 위에 딱 하나의 색.** 앱 전체가 흑백이라 러너의 레벨 색과 사용자가 고른 캔버스 색만 살아난다.

| 항목 | 값 |
|---|---|
| 이름 표기 | `RunCanvas` (붙여 쓰기, R·C 대문자). 한글 화면 이름은 그대로 RunCanvas, 꾸미기 기능만 "런꾸" |
| 톤 | 담백·정직·운동. 화려하지 않고 기록 자체가 주인공 |
| 무드 키워드 | monochrome, flat, bold, kinetic, sticker |
| 브랜드 색 | 검정 `000000` / 흰색 `FFFFFF` + 포인트 **볼트 `CFFF00`**(최고 레벨 색. 로고·마케팅에서 유일하게 허용하는 색) |
| 글꼴 성격 | 시스템 산세리프(SF), 굵은 무게. 숫자는 모노스페이스 |
| 상징 | 달리는 사람(`figure.run`) + 경로 선/붓 선 |
| 피할 것 | 그라데이션·글로시·3D·그림자, 이모지, 초록/파랑 같은 "운동앱 기본색", 여러 색 동시 사용 |

### 앱 아이콘 · 로고 규칙

현재 아이콘(2026-09-16): 흰 배경, 검정 실루엣 러너, 발 아래 볼트색 곡선 한 획. 이 구성을 기준으로 다듬는다.

- **한 가지 형태, 한 가지 색.** 검정 러너 + 볼트 한 획. 획은 "경로"이자 "붓질"(Canvas)이라는 뜻을 같이 가진다.
- 배경은 단색(흰 또는 검정). 다크 아이콘·틴트 아이콘 변형은 러너를 흰색으로 뒤집으면 된다.
- 텍스트 없음. 이름은 앱 이름 자리에서 읽힌다.
- iOS 스쿼클 마스크 안에서 여백 12% 이상. 60pt(홈 화면)·29pt(설정)에서도 실루엣과 획이 구분돼야 하므로 획 두께는 캔버스 폭의 4% 이상.
- 러너는 평면 실루엣. 얼굴·옷·디테일 없음. 앞으로 기운 자세(속도감).
- 볼트 획은 곡선 한 번, 러너 발 뒤에서 앞으로. 끝은 둥글게.
- 산출물: 1024×1024 PNG(투명 없음), 라이트/다크/틴트 3종. 파일은 `RunCanvas/Assets.xcassets/AppIcon.appiconset/`.

로고 프롬프트 뼈대(Claude Design·이미지 생성기 공용):

```
flat vector app icon, bold black running figure silhouette leaning forward, a single thick neon-lime (#CFFF00) brush stroke curving under the feet like a route line, pure white background, centered, generous margins, no text, no gradient, no shadow, no 3D, minimal, high contrast, Nike Run Club-like simplicity
```

네거티브: `text, letters, gradient, glossy, 3d, shadow, multiple colors, background scene, frame, border`

## 원칙

1. **앱은 흑백, 색은 딱 세 곳** — 주요 버튼(레벨 컬러), 홈 지도의 내 위치 점(레벨 컬러), 사용자가 꾸미는 캔버스. 탭·링크·차트·진행바·아이콘은 색을 쓰지 않는다.
2. **시스템 우선** — 색은 `.primary/.secondary/.systemBackground`, 글꼴은 텍스트 스타일(`.headline` 등), 빈 화면은 `ContentUnavailableView`. 커스텀은 그 다음.
3. **선택은 반전으로** — 고른 칩·필터는 검정 바탕 + 흰 글씨. 색 없이도 상태가 보인다.
4. **터치 영역 44pt** — 보이는 크기는 작게 두고 `frame(minHeight: 44)` 또는 `hitTarget()`으로 넓힌다.
5. **이모지 없음, 새 색 없음, 라운드 14~16** — GATES C3 테마 규칙.

## 토큰

### 색

| 토큰 | 값 | 쓰는 곳 |
|---|---|---|
| 배경 | `Color(.systemBackground)` (흰/검정) | 모든 화면 배경 |
| 카드 | `Color.card` = `gray.opacity(0.08)` | 홈·기록·설정 셀·보조 버튼·안 고른 칩 |
| 글자 | `.primary` / `.secondary` / `.tertiary` | 본문 / 보조 설명·라벨 / 힌트 |
| 반전 | `Color.primary` 바탕 + `Color(.systemBackground)` 글자 | 고른 칩, 레벨 없을 때의 주요 버튼 |
| 아바타 자리 | `gray.opacity(0.15)` | `AvatarView` 원형 배경 |
| 오류·삭제 | `.red` | 폼 검증 메시지, 코스 이탈 50m 초과, 삭제 버튼 `tint(.red)` |
| 시작점 | `.green` | 경로 지도의 시작 점(끝 점은 `.red`) |

앱 틴트(`AccentColor`)는 비어 있다 → 시스템 흑백. 그대로 둔다.

### 레벨 컬러 (`Level.Tier.color`, NRC 팔레트)

**`PrimaryButton`·홈 러닝 시작 버튼·홈 지도의 내 위치 점에만 쓴다.** 다른 곳에 물들이지 않는다.

위치 점은 탭 틴트가 `.primary`라 그냥 두면 검게 나온다 — 홈 지도에서만 `.tint(tier?.accent ?? .primary)`로 되돌린다. 러닝 중·기록 상세 지도는 경로 선이 이미 페이스 색을 쓰므로 여기서 제외한다.

| 레벨 | 누적 거리 | hex | 위 글자 |
|---|---|---|---|
| 옐로 | 0 | `F5C417` | 검정 |
| 오렌지 | 50 km | `F26B1C` | 흰색 |
| 그린 | 250 km | `2EB84D` | 흰색 |
| 블루 | 1,000 km | `1F70E8` | 흰색 |
| 퍼플 | 2,500 km | `7A3DE8` | 흰색 |
| 블랙 | 5,000 km | `121212` → 버튼에선 `.primary` | `.systemBackground` |
| 볼트 | 15,000 km | `CFFF00` | 검정 |

- `tier.accent` / `tier.onAccent`를 쓴다(`color`/`foreground` 직접 쓰지 말 것). 블랙 레벨은 다크 모드에서 검정 위 검정이 되므로 `accent`가 흑백으로 바꿔 준다.
- 레벨은 `@Environment(\.levelTier)`로 내려온다. `RootTabView`가 넣고, 로그인 전은 `nil`(흑백).

### 캔버스(런꾸) 전용 색 — 앱 톤의 의도적 예외

편집기 크롬만 다크. 캔버스가 유일하게 밝아야 사용자가 색을 판단할 수 있다. 이 화면 밖에서 쓰지 않는다.

| 토큰 | 값 |
|---|---|
| `Studio.background` | `0E0E10` |
| `Studio.surface` | `white.opacity(0.12)` |
| `Studio.dim` | `white.opacity(0.45)` |

배경 프리셋 (`CanvasPreset`, 좌상→우하 그러데이션):

| 프리셋 | 시작 | 끝 | 글자 |
|---|---|---|---|
| 미드나잇 | `0A0D17` | `2B334F` | 흰색 |
| 선라이즈 | `FFBA6B` | `F05259` | 흰색 |
| 포레스트 | `144533` | `66A859` | 흰색 |
| 오션 | `144D8C` | `33BAC7` | 흰색 |
| 라벤더 | `593D8C` | `D4A8E8` | 흰색 |
| 페이퍼 | `F5F0E0` | `D1C7B0` | 검정 |

사진 배경은 `black.opacity(0.12)` 오버레이 + 흰 글자.

스티커 팔레트 (`Studio.swatches`, 설정의 `CanvasTheme.presets`와 hex가 같아야 한다):
흰색 `FFFFFF` · 검정 `000000` · 옐로 `F5C417` · 오렌지 `F26B1C` · 코랄 `F0525A` · 그린 `66A859` · 민트 `33BAC7` · 라벤더 `D4A8E8`
배경과 밝기 차가 0.25 미만이면 배경 대비색(흰/검정)으로 물러난다(`CanvasTheme.resolvedColor`).

### 타이포그래피

시스템 텍스트 스타일만 쓴다. Dynamic Type을 공짜로 얻는다.

| 용도 | 스타일 |
|---|---|
| 큰 제목 | `.largeTitle` |
| 섹션 제목 | `.title3.weight(.semibold)` |
| 카드 제목·버튼·값 | `.headline` |
| 본문·칩·필터 | `.subheadline` / `.subheadline.weight(.semibold)` |
| 보조 설명 | `.footnote` / `.caption` (`.secondary`) |
| 배지·라벨 | `.caption2.weight(.bold)` |

숫자 규칙:
- 바뀌는 숫자(거리·시간·페이스·카운트)는 `.monospacedDigit()`.
- 한 줄 값은 `lineLimit(1)` + `minimumScaleFactor(0.6~0.8)`.
- 히어로 숫자만 `.system(size:, weight: .bold)` 허용. 현재 쓰이는 크기는 러닝 중 64 / 상세 56 / 홈 52 / 통계 40 / 정산·트레이닝 72~78. 새 화면은 이 중 하나를 고른다.

스티커 글꼴 3종 (`CanvasSticker.FontStyle`) — 골격부터 다르게:

| 이름 | design | weight | tracking |
|---|---|---|---|
| 모던 | `.default` | `.black` | −1 |
| 세리프 | `.serif` | `.semibold` | 0 |
| 라운드 | `.rounded` | `.heavy` | −0.5 |

### 간격

| 값 | 용도 |
|---|---|
| 20 | 화면 좌우 여백, 칩 줄 좌우 |
| 16 | 카드 안 패딩(`.padding()`), 보조 버튼 좌우 |
| 14 | 토스트 패딩, 카드 내부 그룹 |
| 12 | 기본 VStack 간격 |
| 8 · 6 · 4 | 라벨 묶음, 칩 사이(7), 아이콘–텍스트 |
| 24 | 섹션 사이 |

### 라운드

| 값 | 용도 |
|---|---|
| 16 | 카드, 보조 버튼, 토스트, 지도 위 패널 |
| 14 | 주요 버튼 |
| Capsule | 칩, 필터 알약, 지도 위 작은 컨트롤 |
| Circle | 아바타, 스티커 색 견본, 경로 시작·끝 점 |

10·18·9·4는 예외(뱃지 아트·썸네일). 새로 쓰지 않는다.

### 머티리얼·그림자

- `.regularMaterial` — 지도 위 패널, 뱃지 토스트, 경로 없음 상태.
- `.ultraThinMaterial` — 지도 위 캡슐 버튼.
- 그림자는 토스트 한 곳만: `.black.opacity(0.12), radius: 12, y: 4`. 카드엔 그림자 없음.

### 모션

앱 전체에 세 가지뿐. 새 애니메이션은 이 중에서 고른다.

| 값 | 용도 |
|---|---|
| `.snappy(duration: 0.22)` | 선택·토글 |
| `.easeInOut(duration: 0.25)` | 등장·사라짐 |
| `.spring(duration: 0.4)` | 카드·시트 이동 |

토스트 전환은 `.move(edge: .top) + .opacity`, 3초 뒤 사라짐.

## 컴포넌트 (`RunCanvas/Components/`)

| 컴포넌트 | 모양 | 쓰는 곳 | 규칙 |
|---|---|---|---|
| `PrimaryButton` / `PrimaryButtonLabel` | 레벨 컬러 바탕, `.headline`, 라운드 14, 가로 꽉 | 러닝 시작·저장·다음 등 화면당 1개 | 비활성이면 0.35로 흐려짐(자동). `NavigationLink`엔 Label만 |
| `SecondaryButton` / `SecondaryButtonLabel` | `Color.card` 바탕, 아이콘+텍스트, 높이 52, 라운드 16 | 사진 고르기·공유·보조 액션 | `isLoading`이면 아이콘 자리에 스피너. `PhotosPicker`·`ShareLink`엔 Label만 |
| `ChipRow` | 가로 스크롤 캡슐, 고르면 반전 | 마라톤·코스 카테고리 | 값이 많아 스크롤이 두 화면 넘으면 `FilterMenuPill` |
| `FilterMenuPill` | 캡슐 + `chevron.down`, 누르면 메뉴 | 지역 등 값 많은 필터 | 좁혀져 있으면 반전 + 개수 표시 |
| `StatLabel` | `.caption` 제목 + `.headline` 값(모노 숫자) | 러닝 중·결과·상세 | 가로 꽉, 한 줄 축소 |
| `AvatarView` | 원형, 기본 44 | 홈·설정·프로필 | 로드 실패 시 사람 아이콘(스피너 안 돎) |
| `appListTone()` | 인셋 그룹 List를 홈 톤으로 | 설정류 화면 | `listRowBackground(Color.card)`와 함께 |
| `BadgeEarnedToast` | 머티리얼 카드, 뱃지 겹침 | 러닝 종료 후 | `.badgeEarnedToast($newBadges)` 로 붙임. VoiceOver 안내 포함 |
| `AppleSignInButton` | Apple 기본 `.black` 스타일 | 로그인 | 설정의 "연결"은 `AppleAuthorizer` |

카드는 컴포넌트가 아니라 조합이다:

```swift
VStack { … }
    .padding()                       // 16
    .background(Color.card)
    .clipShape(RoundedRectangle(cornerRadius: 16))
```

## 패턴

- **빈 상태** — `ContentUnavailableView("기록이 없어요", systemImage: "figure.run")`. 설명은 한 줄, 해요체.
- **확인·오류** — 시스템 `.alert` / `.confirmationDialog`. 커스텀 모달 없음. 파괴 액션은 `.destructive` 역할.
- **지도 위 컨트롤** — 머티리얼 캡슐(작은 버튼) / 머티리얼 라운드 16 패널(정보).
- **선택 상태** — 반전 + `accessibilityAddTraits(.isSelected)`.
- **문구** — 해요체, 짧게. 예: "다시 시도해 주세요", "새 뱃지를 땄어요".
- **아이콘** — SF Symbols만. 러닝 `figure.run`, 이동 `chevron.right`, 펼침 `chevron.down`.
- **워치** — 값은 `.rounded` 굵은 숫자. 시작 `.green`, 일시정지 `.orange`, 페이스 `.yellow`는 워치 전용(작은 화면에서 색 없이는 구분이 안 됨). 폰으로 가져오지 않는다.

## 접근성

- 터치 44pt: `frame(minHeight: 44)` + `contentShape` 또는 `hitTarget()`.
- 아이콘만 있는 버튼엔 `accessibilityLabel`. 상태가 있는 컨트롤은 "지역, 현재 서울"처럼 현재값까지.
- 장식 이미지는 `accessibilityHidden(true)`. 카드처럼 한 덩어리는 `accessibilityElement(children: .combine)`.
- 텍스트 스타일을 써서 Dynamic Type 대응. 고정 크기는 히어로 숫자만.
- 대비: 캔버스 스티커는 `CanvasTheme.resolvedColor`가 배경에 묻히는 색을 막는다.

## 하지 말 것

| 하지 말 것 | 대신 |
|---|---|
| 탭·링크·차트에 레벨 컬러 | 흑백 유지. 레벨 컬러는 `PrimaryButton`과 홈 지도의 내 위치 점만 |
| `Color(red:green:blue:)` 새로 만들기 | `Theme.swift` 토큰. 정말 필요하면 hex로 `CanvasTheme.color(hex:)` |
| 이모지 | SF Symbol |
| 카드에 그림자 | `Color.card` 평면 |
| 커스텀 알럿·토스트 | 시스템 `.alert`, 토스트는 `BadgeEarnedToast` 패턴 |
| `.font(.system(size: 15))` 같은 본문 고정 크기 | `.subheadline` |
| 새 라운드 값 | 16 / 14 / Capsule |
| 새 애니메이션 곡선 | snappy 0.22 / easeInOut 0.25 / spring 0.4 |

## 현재 편차 (2026-09-16 스캔)

고칠 때 참고. 규칙을 깬 건 아니고 통일이 덜 된 것.

- 본문 고정 크기 `.system(size: 15/14/12)` 8곳 → 텍스트 스타일로.
- 히어로 숫자 크기 7종(40~78) → 3단계(72 / 56 / 40) 정도로 줄이면 좋다.
- `cornerRadius` 10·18·9·4 — 뱃지 아트·썸네일. 그대로 둬도 되나 새로 늘리지 않는다.
- 경로 지도 페이스 색은 `RouteMapView`에 계산식으로 있다(빨강→노랑). 팔레트 밖이지만 데이터 시각화라 예외.
- `Color.card` 사용 17개 파일, `PrimaryButton` 13개 — 채택은 충분. `ChipRow`는 1곳(코스는 `FilterMenuPill`로 바꿈).

## PR 체크 (GATES C3)

- [ ] 새 색 0건 (`Color(red:` grep)
- [ ] 이모지 0건
- [ ] 라운드 14~16 또는 Capsule
- [ ] 주요 버튼은 `PrimaryButton`, 보조는 `SecondaryButton`
- [ ] 터치 영역 44pt
- [ ] 텍스트 스타일 사용(고정 크기는 히어로 숫자만)

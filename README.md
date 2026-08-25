# RunCanvas

iOS app (SwiftUI, Xcode 26, iOS 18.5+).

`RunCanvas.xcodeproj` 를 Xcode로 열면 됩니다.

## 브랜치 규칙 (git-flow)

| 브랜치 | 용도 | 어디서 → 어디로 |
|---|---|---|
| `main` | 출시된 버전만. 직접 커밋 금지 | `release/*`, `hotfix/*` 머지 |
| `develop` | 다음 버전 통합. 기본 브랜치 | `feature/*` PR 머지 |
| `feature/<이름>` | 기능 하나 | `develop`에서 분기 → `develop`으로 PR |
| `release/<버전>` | 출시 준비(버전 올리기, 버그 수정) | `develop`에서 분기 → `main`+`develop` 머지 |
| `hotfix/<이름>` | 출시 버전 긴급 수정 | `main`에서 분기 → `main`+`develop` 머지 |

- PR은 상대방 리뷰 1명 승인 후 머지.
- `feature/*`, `release/*`, `hotfix/*`는 필요할 때 만들고, 머지 후 삭제.

## 폴더 구조

```
RunCanvas/
├── App/          앱 진입점, RootTabView (탭: 홈·기록·런구·설정)
├── Models/       Run(거리·페이스·시간·BPM·경로·날짜), RunSettings
├── Services/     LocationService(GPS), HealthService(심박·워치), RunStore(저장)
├── Features/     화면 묶음별 폴더 — View + ViewModel을 같은 폴더에
│   ├── Home/       지도 + 최신 기록 카드 + Run Start
│   ├── Running/    러닝 중, 일시정지
│   ├── Records/    주·월·년 그래프 + 목록
│   ├── Canvas/     런구 1~4 (배경 선택 → 기록 선택 → 편집 → 저장·공유)
│   └── Settings/   러닝 설정, Apple Watch
├── Components/   공통 UI (StatLabel, MapView 래퍼, DesignSystem)
└── Assets.xcassets
```

Xcode 동기화 폴더라 Finder에서 폴더·파일을 만들면 프로젝트에 자동 반영됩니다.

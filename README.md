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

# 다음 세션 핸드오프

> 작성: 2026-04-24 (세션 5)
> 이 문서 하나만으로 새 세션이 컨텍스트 없이 이어받을 수 있게 작성됨.

---

## TL;DR — 새 세션에서 바로 할 일

**창 토글 일관성 문제 수정이 1순위.**

메인+세팅 둘 다 열린 상태에서 메인만 X로 닫고 토글하면 세팅만 반복 표시되는 버그. `WindowManager.swift`의 `showAll()` → `reopenViaSwiftUI()` 호출 타이밍/포커스 이슈.

시작점: `Gnomon/App/WindowManager.swift` — `showAll()`, `reopenViaSwiftUI()`

---

## 프로젝트 현재 상태

- 경로: `/Users/sunguk/0.code/0.shipping/moniterpicker/gnomon/`
- GitHub: https://github.com/sunpark20/gnomon (main 브랜치)
- 최신 태그: **v1.7.0** (GitHub Release 배포 완료, 공증+DMG)
- 최신 커밋: `a21ff80` — **push 안 됨** (origin보다 6커밋 ahead)
- 미커밋: `.claude/settings.json` (untracked), `bgraw.md`, `bgwiki.md`
- Gate: `./Scripts/gate.sh --skip-tests` **3/3 통과** (lint / format / build)
  - 테스트는 `LSUIElement: YES` 변경으로 부트스트랩 실패 — 별도 수정 필요
- 홈페이지: https://homeninja.vercel.app/#gnomon

### 배포 파이프라인

```bash
pkill -f Gnomon
xcodegen generate
./Scripts/release.sh  # gate(--skip-tests) → archive → notarize → staple → DMG → GitHub Release
```

Apple Developer 인증 정보:
- Team ID: `GA2LMK5XL2`
- Signing Identity: `Developer ID Application: sunguk park (GA2LMK5XL2)`
- Notary Profile: `gnomon-notary` (Keychain에 저장됨)

빌드:
```bash
cd /Users/sunguk/0.code/0.shipping/moniterpicker/gnomon
xcodegen generate
xcodebuild -scheme Gnomon -configuration Debug build
open /Users/sunguk/Library/Developer/Xcode/DerivedData/Gnomon-cirxpksfouhoawbyhyalyvuxfegs/Build/Products/Debug/Gnomon.app
```

온보딩 테스트 (다른 설정 초기화 없이):
```bash
defaults write com.sunguk.gnomon.Gnomon onboardingCompletedAt -float 0 && open /path/to/Gnomon.app
```

---

## 이번 세션에서 완성된 것 (세션 5 — 코드 품질 정리)

### `/simplify` 리팩토링 ✅ (`fdacc5f`)

| 항목 | 내용 |
|---|---|
| **중복 상태 제거** | `monitorConnected` 저장 프로퍼티 → `activeMonitor != nil` 계산 프로퍼티. 상태 동기화 드리프트 원천 차단 (`AutoLoopController.swift:63`) |
| **Debouncer 재사용** | 수동 Task cancel/sleep 패턴의 `scheduleRediscovery` → 기존 `Debouncer` 유틸리티로 대체. `rediscoveryTask` 프로퍼티 제거 |
| **시작 I/O 절감** | `start()`에서 `listDisplays()` 2회 호출 → 1회로 통합. 결과를 진단 로깅에 재사용 |
| **start/stop 레이스 수정** | fire-and-forget 초기 sync Task → `initialSyncTask`에 저장, `stop()`에서 cancel |
| **retry 일관성** | `userSetBrightness`도 `writeBrightnessWithRetry` 사용하도록 통일 (다른 write 경로와 동일) |
| **모니터 선택 추출** | `monitors.first(where: { !$0.uuid.isEmpty })` 중복 → `pickMonitor(from:)` 헬퍼 |
| **TimelineView 최적화** | 0.1s → 1.0s 틱 (10x body 평가 감소, 실제 데이터 주기와 일치) (`MainWindow.swift:23`) |

### `/su-swift-check-ui` 감사 + 접근성 수정 ✅ (`a21ff80`)

| 항목 | 내용 |
|---|---|
| **Toggle 접근성** | `BrightnessCard` Auto 토글에 `.accessibilityLabel("Auto brightness")` 추가 |
| **Disconnected badge 대비** | 최소 opacity 0.15 → 0.3 (WCAG AA 개선) (`AmbientSensorCard.swift:170`) |
| **UI 감사 보고** | 색상 6건, 폰트 1건, 패딩 1건, 구조 리스크 3건, 접근성 3건 발견 — 아래 TODO에 반영 |

### `/security-review` ✅

보안 취약점 0건. 로컬 전용 앱, 공격 표면 없음 확인.

### `/fewer-permission-prompts` ✅

`.claude/settings.json` 생성. 읽기 전용 명령 5개 패턴 등록 (swiftlint, security, sips).

---

## 미완료 TODO (우선순위 순)

### 1. ⭐⭐⭐ 창 토글 일관성 수정 (예상: 2~3시간)

**현상**: 메인+세팅 열림 → 메인만 X로 닫음 → 토글 시 세팅만 반복 표시.
**관련 파일**: `Gnomon/App/WindowManager.swift` (`showAll`, `reopenViaSwiftUI`)
**왜 필요**: 사용자가 창을 닫았다 열 때 메인이 안 뜨면 앱이 고장난 것처럼 보임.

### 2. ⭐⭐ `LSUIElement` 환경에서 테스트 부트스트랩 수정 (예상: 1시간)

**현상**: `LSUIElement: YES`로 변경 후 `xcodebuild test`가 "Early unexpected exit, operation never finished bootstrapping" 에러.
**원인**: 테스트 러너가 독 아이콘 없는 앱과 연결 실패 + 중복 실행 방지 코드 충돌.
**해결 방향**: `release.sh`에서 `--skip-tests`로 임시 우회 중. AppDelegate 중복 실행 방지를 테스트 환경에서 비활성화하거나, 테스트 타겟에 `LSUIElement: NO` 별도 설정.
**관련 파일**: `Scripts/gate.sh`, `Scripts/release.sh:58`, `Gnomon/App/AppDelegate.swift:19-27`

### 3. ⭐⭐ 카드 패딩/간격/폰트 통일 (예상: 30분)

**현상**: AmbientSensorCard `.padding(32)` vs BrightnessCard/ContrastCard `.padding(24)`. 헤더 spacing 10 vs 8 혼재. 카드 헤더 폰트도 AmbientSensorCard `.title3.bold` vs B/C `.headline` 불일치.
**관련 파일**: `AmbientSensorCard.swift:78,24,27`, `BrightnessCard.swift:30,44,49`, `ContrastCard.swift:23,30,34`
**왜 필요**: UI 감사(`/su-swift-check-ui`)에서 발견된 통일성 불일치.

### 4. ⭐ UI 감사 후속 — 하드코딩 색상/접근성 (예상: 30분)

**현상**: `HotkeyRow.swift:90,96`에서 `NSColor.systemOrange` 사용 (Theme.gold 우회). `OnboardingWindow.swift:64`에서 `.white`, `:116`에서 `.red` 하드코딩 (Theme.error 미정의). 여러 아이콘 버튼에 `.help()` 및 `.accessibilityLabel()` 누락.
**관련 파일**: `HotkeyRow.swift`, `OnboardingWindow.swift`, `BrightnessCard.swift:145`, `ContrastCard.swift:64`
**왜 필요**: 접근성 및 Theme 일관성. NSView 내 NSColor↔Theme 변환 필요.

### 5. ⭐ `BACKGROUND.md` stale 항목 정리 (예상: 15분)

**현상**: "코드 서명, 공증 → 개인용" 항목이 더 이상 맞지 않음 (이제 서명+공증 완료).
**관련 파일**: `BACKGROUND.md`

---

## 활성 곡선 (PRD §5.2.1 v0.4)

```
b(lux) = b_min + (b_max - b_min) × clamp(log10(lux + 1) / log10(2001), 0, 1)
코드 기본값: b_min=0, b_max=100, darkFloorLux=15
EMA: α=0.2, snap: threshold=50, duration=3
```

---

## 현재 기본 단축키

| 액션 | 키 |
|---|---|
| Brightness Up/Down | `⌃⌥⌘ =` / `⌃⌥⌘ -` |
| Contrast Up/Down | `⌃⌥⌘ ]` / `⌃⌥⌘ [` |
| Toggle Auto | `⌃⌥⌘ B` |
| Toggle Window | `⌃⌥⌘ G` |

Carbon 기반 — Accessibility 권한 불필요.

---

## 주요 파일 맵

```
Gnomon/
├── App/
│   ├── GnomonApp.swift            # WindowGroup + 온보딩/메인 조건분기
│   ├── AppDelegate.swift          # 중복 실행 방지 + 메뉴바 셋업
│   ├── StatusBarController.swift
│   └── WindowManager.swift        # ⚠️ 토글 일관성 TODO
├── Services/
│   ├── IconUpdater.swift          # 메뉴바 아이콘만 (독 아이콘 제거됨)
│   └── SundialIconRenderer.swift  # .dock 스타일 미사용, .menuBar만 활성
├── Views/
│   ├── Theme.swift                # GoldToggleStyle, GoldSlider 포함
│   ├── AmbientSensorCard.swift    # overlay 메시지 + Disconnected badge
│   ├── BrightnessCard.swift       # GoldSlider + accessibilityLabel
│   ├── ContrastCard.swift         # GoldSlider + ESC 편집 취소
│   ├── MainWindow.swift           # 1s TimelineView + 10초 메시지 교체
│   ├── Onboarding/
│   │   └── OnboardingWindow.swift # WindowAccessor 520×580 리사이즈
│   └── Settings/
│       └── SettingsWindow.swift   # 영어 통일, ESC 포커스 해제
Scripts/
├── gate.sh                        # --skip-tests 옵션 지원
└── release.sh                     # gate --skip-tests로 호출
```

---

## 관련 문서

- [PRD.md](PRD.md) — 개발자용 명세
- [BACKGROUND.md](BACKGROUND.md) — 제품 스토리
- [research/adaptive-curves.md](research/adaptive-curves.md) — 곡선 학술 근거

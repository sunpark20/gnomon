# 다음 세션 핸드오프

> 작성: 2026-04-21 (세션 3)
> 이 문서 하나만으로 새 세션이 컨텍스트 없이 이어받을 수 있게 작성됨.

---

## TL;DR — 새 세션에서 바로 할 일

**창 토글 일관성 문제 수정이 1순위.**

메인+세팅 둘 다 열린 상태에서 메인만 X로 닫고 토글하면 세팅만 반복 표시되는 버그. Cmd+W(숨기기)는 정상, X 버튼(SwiftUI 파괴) 경로에서 발생. `WindowManager.swift`의 `showAll()` → `reopenViaSwiftUI()` 호출은 동작하지만, 세팅 창과의 상호작용에서 타이밍/포커스 이슈 있음.

시작점: `Gnomon/App/WindowManager.swift` — `showAll()`, `reopenViaSwiftUI()`

---

## 프로젝트 현재 상태

- 경로: `/Users/sunguk/0.code/moniterpicker/gnomon/`
- GitHub: https://github.com/sunpark20/gnomon (main 브랜치)
- 최신 태그: **v1.6.0** (GitHub Release 배포 완료, 공증+DMG)
- 최신 커밋: `6a1bb12` — push 완료
- 미커밋: `BACKGROUND.md` 수정 1건 (문장 추가)
- Gate: `./Scripts/gate.sh` **4/4 통과** (lint / format / build / test)
- 테스트: **49개** (3개는 GNOMON_INTEGRATION=1 필요)
- 홈페이지: https://ninjaturtle.win/#gnomon

### 배포 파이프라인

완전 자동화됨. 한 명령으로 배포:
```bash
pkill -f Gnomon  # 실행 중인 인스턴스 종료 필수 (안 하면 test bootstrap 실패)
xcodegen generate
./Scripts/release.sh  # gate → archive → notarize → staple → DMG → GitHub Release
```

Apple Developer 인증 정보:
- Team ID: `GA2LMK5XL2`
- Signing Identity: `Developer ID Application: sunguk park (GA2LMK5XL2)`
- Notary Profile: `gnomon-notary` (Keychain에 저장됨)

빌드:
```bash
cd /Users/sunguk/0.code/moniterpicker/gnomon
xcodegen generate
./Scripts/gate.sh
xcodebuild -project Gnomon.xcodeproj -scheme Gnomon \
  -configuration Debug -derivedDataPath build -quiet build
open build/Build/Products/Debug/Gnomon.app
```

---

## 이번 세션에서 완성된 것 (v1.3.0 → v1.6.0)

### 배포 파이프라인 완성 ✅

| 항목 | 내용 |
|---|---|
| **release.sh** | Team ID/Signing Identity 기본값 설정, BSD sed 호환 버전 파싱 수정 |
| **project.yml** | `ENABLE_HARDENED_RUNTIME: YES` 추가 (notarization 필수) |
| **Notarization** | `gnomon-notary` Keychain 프로필 설정 완료 |
| **v1.4.0~v1.6.0** | 3개 버전 GitHub Release 배포 성공 |

### 창 관리 버그 수정 ✅ (부분)

| 항목 | 내용 |
|---|---|
| **WindowManager.swift** | Cmd+W → `NSEvent.addLocalMonitorForEvents`로 인터셉트하여 `orderOut` (숨기기) 처리. X 버튼 닫기 시 `reopenViaSwiftUI()`로 File 메뉴 "New Gnomon Window" 트리거하여 재생성 |
| **AppDelegate.swift** | `applicationShouldHandleReopen`에서 `show()` 제거 → Dock 더블 창 방지 |

### 기타

| 항목 | 내용 |
|---|---|
| **SettingsWindow.swift** | 버전 표시 하드코딩(`v1.1.0`) → `Bundle.main` CFBundleShortVersionString 동적 읽기 |
| **SettingsWindow.swift** | Bug Report 행에 홈페이지 아이콘(house) 추가 → `ninjaturtle.win/#gnomon` |
| **BACKGROUND.md** | Intel Mac 미지원 항목 추가, Software Dim 미구현 사유 추가 |
| **BrightnessCurveTests.swift** | 코드 기본값(min=0, max=100, darkFloor=15) 변경에 맞춰 테스트 기대값 수정 |

---

## 미완료 TODO (우선순위 순)

### 1. ⭐⭐⭐ 창 토글 일관성 수정 (예상: 2~3시간)

**현상**: 메인+세팅 열림 → 메인만 X로 닫음 → 토글 시 세팅만 반복 표시. 세팅까지 닫아도 세팅만 뜸.
**원인 추정**: `reopenViaSwiftUI()`가 비동기로 새 창을 만드는데, `showAll()`에서 세팅 `makeKeyAndOrderFront`가 먼저 실행되어 포커스를 가져감. 또는 `reopenViaSwiftUI`의 File 메뉴 perform이 세팅 창 컨텍스트에서 실행되는 문제일 수 있음.
**관련 파일**: `Gnomon/App/WindowManager.swift` (`showAll`, `reopenViaSwiftUI`)
**왜 필요**: 사용자가 창을 닫았다 열 때 메인이 안 뜨면 앱이 고장난 것처럼 보임.

### 2. ⭐⭐ `gate.sh` 테스트 단계 안정성 (예상: 30분)

**현상**: Gnomon 프로세스가 실행 중일 때 `xcodebuild test`가 "Early unexpected exit, operation never finished bootstrapping" 에러로 실패.
**원인**: 테스트 러너가 Gnomon 앱을 부트스트랩할 때 기존 인스턴스와 충돌 (중복 실행 방지 코드가 테스트 호스트도 종료시킴).
**해결 방향**: `gate.sh` 시작 시 `pkill -f Gnomon` 추가하거나, AppDelegate 중복 실행 방지를 테스트 환경에서 비활성화.
**관련 파일**: `Scripts/gate.sh`, `Gnomon/App/AppDelegate.swift:19-27`

### 3. ⭐ `BACKGROUND.md`의 stale 항목 정리 (예상: 15분)

**현상**: "코드 서명, 공증, 자동 업데이트 → 개인용, GitHub에서 받아 빌드" 항목이 더 이상 맞지 않음 (이제 서명+공증 완료). "알려진 한계" 5번도 업데이트 필요.
**관련 파일**: `BACKGROUND.md:60`, `BACKGROUND.md:249`

---

## 활성 곡선 (PRD §5.2.1 v0.4)

```
b(lux) = b_min + (b_max - b_min) × clamp(log10(lux + 1) / log10(2001), 0, 1)
코드 기본값: b_min=0, b_max=100, darkFloorLux=15
PRD 권장값: b_min=20, b_max=95, darkFloorLux=3
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
│   ├── GnomonApp.swift
│   ├── AppDelegate.swift          # 중복 실행 방지 + Dock reopen
│   ├── StatusBarController.swift
│   └── WindowManager.swift        # ⚠️ 토글 일관성 TODO
├── Services/
│   ├── NativeDDC.swift            # IOAVService DDC/CI
│   ├── HotkeyManager.swift        # Carbon RegisterEventHotKey
│   ├── M1DDCClient.swift          # NativeDDC 래퍼
│   ├── LuxReader.swift            # corebrightnessdiag (시스템 바이너리)
│   ├── ProcessRunner.swift        # LuxReader용
│   ├── CSVLogger.swift
│   ├── Debouncer.swift
│   ├── IconUpdater.swift
│   └── SundialIconRenderer.swift
├── ViewModels/
│   ├── AutoLoopController.swift
│   └── OnboardingViewModel.swift
└── Views/
    └── Settings/
        └── SettingsWindow.swift   # 홈페이지 링크, 동적 버전 표시
Scripts/
├── gate.sh                        # lint + format + build + test
└── release.sh                     # 릴리즈 파이프라인 (완성)
```

---

## 관련 문서

- [PRD.md](PRD.md) — 개발자용 명세
- [BACKGROUND.md](BACKGROUND.md) — 제품 스토리
- [research/adaptive-curves.md](research/adaptive-curves.md) — 곡선 학술 근거

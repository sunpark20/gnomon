# 다음 세션 핸드오프

> 작성: 2026-04-21 (세션 2)
> 이 문서는 새 Claude 세션이 컨텍스트 없이 바로 이어받을 수 있게 작성됨.

---

## TL;DR — 새 세션에서 바로 할 일

**자체 배포 파이프라인 완성이 남은 유일한 블로커.**

1. ~~**Carbon hotkey 교체**~~ ✅
2. ~~**m1ddc 네이티브 포팅**~~ ✅
3. **corebrightnessdiag 셸아웃 제거** — 보류 (아래 사유)
4. **Developer ID 서명 + Notarization + DMG 파이프라인** ← 다음 1순위

### Phase 3 보류 사유
`corebrightnessdiag`는 macOS 시스템 바이너리(항상 존재). 네이티브 IOKit HID 접근은 root 권한 필요 + 문서화 안 된 HID 리포트 파싱 필요 → 위험 대비 이점 낮음. Developer ID 배포(비샌드박스)에서는 `/usr/libexec/` 접근 문제 없음.

### Phase 4 필요한 것
- **Apple Developer Program 가입** ($99/년) — 이것만 하면 나머지는 `Scripts/release.sh` 실행 한 방
- 가입 후: `export GNOMON_TEAM_ID="YOUR_TEAM_ID"` 설정
- `Scripts/release.sh` 이미 작성됨: archive → notarize → staple → DMG → GitHub Release

---

## 프로젝트 위치 / 상태

- 경로: `/Users/sunguk/0.code/moniterpicker/gnomon/`
- GitHub: https://github.com/sunpark20/gnomon (main 브랜치)
- 최신 상태: 아직 미커밋 — 아래 변경사항이 working tree에 있음
- Gate: `./Scripts/gate.sh` **4/4 통과** (lint / format / build / test)
- 테스트: **49개** (3개는 GNOMON_INTEGRATION=1 필요)
- **외부 바이너리 의존: m1ddc 제거됨** (IOAVService 네이티브), corebrightnessdiag만 남음 (시스템 바이너리)

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

## 이번 세션에서 완성된 것

### Phase 1: Carbon hotkey 교체 ✅

| 변경 | 내용 |
|---|---|
| **HotkeyManager.swift** | `NSEvent.addGlobalMonitorForEvents` → Carbon `RegisterEventHotKey`. Accessibility 권한 완전 불필요 |
| **AccessibilityChecker.swift** | 삭제 |
| **OnboardingViewModel.swift** | Accessibility 체크 제거 |
| **OnboardingWindow.swift** | Accessibility 체크 행 제거 |

### Phase 2: m1ddc 네이티브 포팅 ✅

| 변경 | 내용 |
|---|---|
| **NativeDDC.swift** (신규) | IOAVService 직접 호출. `DCPAVServiceProxy` IOKit 매칭 → `IOAVServiceCreateWithService` → DDC/CI I2C 프로토콜 (Get/Set VCP Feature). 디스플레이 이름은 IOKit `DisplayProductName` 프로퍼티에서 추출 |
| **M1DDCClient.swift** | ProcessRunner 셸아웃 제거 → NativeDDC 호출. `Task.detached`로 I2C 블로킹(40ms usleep) 격리. 같은 public API 유지 |
| **OnboardingViewModel.swift** | m1ddc 미설치 에러 핸들링 제거 (네이티브이므로 불필요) |
| **MonitorID.swift** | uuid 필드가 IOKit registry entry ID를 저장하도록 변경 |

### 버그 수정 & 인프라

| 변경 | 내용 |
|---|---|
| **AppDelegate.swift** | 앱 중복 실행 방지 (같은 bundle ID 이미 실행 중이면 terminate) |
| **gate.sh** | xcbeautify 오탐 수정 (`PIPESTATUS[0]` 사용) |
| **project.yml** | `백업/` 디렉토리 exclude |
| **WindowAccessor.swift** | 디스크 누락 파일 복원 |
| **AmbientSensorCard.swift** | trailing newline 추가 |
| **Scripts/release.sh** (신규) | Developer ID 서명 + Notarization + DMG + GitHub Release 파이프라인 스크립트 |

---

## 검증 필요 사항 (사용자)

### Carbon hotkey
1. 앱 빌드 후 `⌃⌥⌘ =/-/]/[/B/G` 전부 동작 확인 (앱 백그라운드일 때도)
2. Accessibility 권한 프롬프트가 안 뜨는지 확인
3. Settings → Hotkeys 더블클릭 재할당 동작 확인

### 네이티브 DDC
4. 앱 시작 시 외부 모니터 감지되는지 확인 (Onboarding 체크리스트)
5. 자동 밝기 조절 동작 확인 (m1ddc 없이!)
6. 수동 밝기/대비 슬라이더 동작 확인

### 기타
7. 앱 아이콘 여러 번 찍어도 1개만 실행되는지 확인
8. `defaults delete com.sunguk.gnomon.Gnomon` 후 Onboarding 흐름 확인 (2개 체크만)

---

## 활성 곡선 (PRD §5.2.1 v0.4)

```
b(lux) = b_min + (b_max - b_min) × clamp(log10(lux + 1) / log10(2001), 0, 1)
b_min=20, b_max=95 (UserDefaults)
darkFloorLux=3 (lux ≤ 3 → b_min)
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
│   ├── AppDelegate.swift          # 중복 실행 방지
│   ├── StatusBarController.swift
│   └── WindowManager.swift
├── Services/
│   ├── NativeDDC.swift            # ✅ IOAVService DDC/CI (신규)
│   ├── HotkeyManager.swift        # ✅ Carbon RegisterEventHotKey
│   ├── M1DDCClient.swift          # ✅ NativeDDC 래퍼 (셸아웃 제거)
│   ├── LuxReader.swift            # corebrightnessdiag (시스템 바이너리)
│   ├── ProcessRunner.swift        # LuxReader용으로 유지
│   ├── CSVLogger.swift
│   ├── Debouncer.swift
│   ├── IconUpdater.swift
│   └── SundialIconRenderer.swift
├── ViewModels/
│   ├── AutoLoopController.swift
│   └── OnboardingViewModel.swift
└── Views/ ...
Scripts/
├── gate.sh                        # lint + format + build + test
└── release.sh                     # ✅ 릴리즈 파이프라인 (신규)
```

**제거된 파일**: `AccessibilityChecker.swift`, `Views/StatusBar.swift`

---

## 관련 문서

- [PRD.md](PRD.md) — 개발자용 명세
- [BACKGROUND.md](BACKGROUND.md) — 제품 스토리
- [research/adaptive-curves.md](research/adaptive-curves.md) — 곡선 학술 근거

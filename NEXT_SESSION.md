# 다음 세션 핸드오프

> 작성: 2026-04-21
> 이 문서는 새 Claude 세션이 컨텍스트 없이 바로 이어받을 수 있게 작성됨.

---

## TL;DR — 새 세션에서 바로 할 일

**배포 목표 확정**: Mac App Store 포기. **Developer ID + Notarization**으로 자체 배포 (GitHub Releases / 본인 웹).
Gnomon 같은 DDC 앱은 MAS 심사 통과한 전례가 없음 (Lunar, BetterDisplay, MonitorControl 전부 자체 배포). 결론 근거는 아래 "배포 전략" 섹션.

**자체 배포 준비 로드맵** (작업 완료 순서대로):

1. **Carbon hotkey 교체** (가장 쉬움, 0.5일)
   - 현재 `NSEvent.addGlobalMonitorForEvents` → Accessibility 권한 요구
   - Carbon `RegisterEventHotKey`로 교체 → **Accessibility 불필요**
   - 참조: [soffes/HotKey](https://github.com/soffes/HotKey) / [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)
   - 수정 대상: `Gnomon/Services/HotkeyManager.swift` + `AccessibilityChecker.swift` 제거 가능성
   - 주의 (macOS 15+): hotkey modifier에 Cmd 또는 Ctrl 하나는 필수

2. **m1ddc 네이티브 포팅** (사용자 경험 최대 개선, 1~2일)
   - 현재 `/opt/homebrew/bin/m1ddc` 외부 바이너리 의존 → 사용자가 `brew install m1ddc` 해야 함
   - `IOAVService` (`IOAVServiceCreate` + `IOAVServiceWriteI2C`) 직접 호출로 교체
   - MIT 라이선스 레퍼런스: [MonitorControl Arm64DDC.swift](https://github.com/MonitorControl/MonitorControl/blob/main/MonitorControl/Support/Arm64DDC.swift)
   - 수정 대상: `Gnomon/Services/M1DDCClient.swift` 재작성 (+ `ProcessRunner` 사용 제거 가능)

3. **corebrightnessdiag 셸아웃 제거** (notarization 친화, 1~2일)
   - 현재 `/usr/libexec/corebrightnessdiag status-info` 파싱
   - Apple Silicon: `AppleSPUHIDDevice` 직접 HID 쿼리 또는 내장 디스플레이 밝기 KVO
   - 외부 바이너리 0개 되면 심사/배포 완전 자체 완결
   - 수정 대상: `Gnomon/Services/LuxReader.swift`

4. **Developer ID 서명 + Notarization + DMG 파이프라인** (0.5일)
   - Apple Developer Program $99/년 가입
   - Xcode "Developer ID Application" 인증서 설정
   - `Scripts/release.sh` 스크립트: `xcodebuild archive` → `xcrun notarytool submit` → `xcrun stapler staple` → `create-dmg`
   - GitHub Releases 자동 업로드 (`gh release create`)

**권장 순서**: 1 → 2 → 3 → 4. 1, 2만 해도 사용성 크게 개선되므로 단계별 릴리즈 가능.

---

## 프로젝트 위치 / 상태

- 경로: `/Users/sunguk/0.code/moniterpicker/gnomon/`
- GitHub: https://github.com/sunpark20/gnomon (main 브랜치)
- 최신 커밋: **v1.3.0** (`9588da0`) — 이번 세션 전체를 한 커밋으로 푸시됨
- Gate: `./Scripts/gate.sh` **4/4 통과** (lint / format / build / test)
- 테스트: **48개** (3개는 GNOMON_INTEGRATION=1 필요)

빌드:
```bash
cd /Users/sunguk/0.code/moniterpicker/gnomon
xcodegen generate              # .xcodeproj 재생성 (필요 시)
./Scripts/gate.sh              # 모든 검증 1회
xcodebuild -project Gnomon.xcodeproj -scheme Gnomon \
  -configuration Debug -derivedDataPath build -quiet build
open build/Build/Products/Debug/Gnomon.app
```

**빌드/실행 주의사항** (이번 세션에서 발견):
- Xcode Run 버튼 쓴 적 있으면 Xcode 창에서 반드시 **Stop(⏹)** 눌러서 종료. 그러지 않으면 `debugserver`가 프로세스를 물고 있어서 `pkill`이 안 먹고, 새 빌드 `open` 해도 같은 bundle id라 좀비에 focus만 감.
- CLI로 일관되게 가는 걸 추천. `pkill -x Gnomon && open build/.../Gnomon.app`.

---

## 이번 세션에서 완성된 것 (v1.2.2 → v1.3.0)

### 반응성 (핵심 이슈 "찔끔찔끔" 해결)

| 기능 | 내용 |
|---|---|
| **Big-delta snap** | `EMAFilter`에 `snapThreshold=50, snapDuration=3` 추가. 1초 샘플 3개 연속 ±50 lux 벌어지면 EMA 우회하고 raw로 점프. 단발성 스파이크는 counter 리셋으로 무시 |
| **snap 즉시 DDC push** | snap 발동 시 sync interval 기다리지 않고 즉시 DDC 명령 전송. 30초 interval이어도 급변은 3초 내 반영. sync timer는 push 직후 재시작해서 이중 송신 방지 |
| **darkFloor** | `BrightnessCurve.Parameters.darkFloorLux=3`. macOS 센서가 완전 가려도 ~1–3 lux 반환하는 특성 반영 → `lux ≤ 3`이면 바로 `b_min` 반환. 이전엔 target이 30 근처에서 멈춤 |

### Settings UX

- **Brightness Min/Max** Enter 적용 패턴 (Interval과 통일): pending 시 gold 외곽선 + "Enter로 적용" 힌트 + focus 이탈 시 auto-commit
- **Interval 레이아웃**: hint 공간을 `opacity`로 예약 → 입력 중에 프리셋 버튼이 밀리는 튐 제거
- **Sync tip 문구**: "인터벌과 상관없이 급격한 조도 변화는 즉시 반영됩니다." 추가
- **Active Monitor 행 제거** (카드에서 이미 노출됨)

### 메뉴바 아이콘

- 해시계 그림자를 **24시간 시계 방향**으로 전환 (00:00=위, 06:00=오른쪽, 12:00=아래, 18:00=왼쪽)
- **분(minute) 보간** + 1분 간격 refresh + **KST(Asia/Seoul) 고정** + `NSWorkspace.didWakeNotification` 연결 (sleep 복귀 즉시 재그리기)
- Localize 필요 시 TODO — 지금은 KST hard-coded

### 안정성 / 진단

- **Auto 토글 황금색**: `.tint(Theme.gold)` — active/inactive 창 상태 모두에서 유지
- **Contrast 방어**: `m1ddc getContrast`가 0 반환하면 무시하고 default 70 유지 (일시적 실패에 슬라이더가 0으로 망가지던 버그)
- **Contrast "Reset 70"** 링크 추가 (이미 0으로 망가졌을 때 한 번에 복구)
- **CSV 로그 스키마 v2**: `b_min`, `b_max` 칼럼 추가 → UserDefaults 오염 같은 상황을 역산 없이 바로 진단 가능. `ensureFile`이 기존 8칼럼 파일을 `log.csv.v1`로 자동 백업 후 새 파일 생성 (데이터 손실 없음)

### 테스트

- snap flag 동작 / darkFloor 경계값 / 스키마 자동 백업 시나리오 추가
- **48 tests, 0 failures, 3 skipped**

---

## 배포 전략 (MAS 포기 근거)

**Mac App Store는 아래 3가지 이유로 현실적 불가**:

1. **DDC/CI 사용**: `IOAVService*` private API 요구. Apple 심사가 2021년 이후 지속적으로 거부. 경쟁사 전부 MAS 포기:
   - Lunar, BetterDisplay, MonitorControl → **모두 자체 배포**
   - MonitorControl Lite만 MAS에 있음 — **DDC 제거하고 gamma dimming 소프트웨어 방식**으로 축소
2. **Ambient light sensor 직접 읽기**: sandbox에서 `/usr/libexec/*` 셸아웃 불가. IOKit HID 직접 접근도 sandbox 제약
3. **Homebrew m1ddc 의존**: sandbox가 임의 외부 바이너리 실행 불가

**결정**: 자체 배포 (Developer ID + Notarization). Lunar, Raycast, Rectangle, BetterDisplay 등이 다 같은 방식으로 잘 돌아가고 있음.

**혹시 MAS 진입이 절실해지면**: Gnomon Lite (software dimming only)를 별도 타겟으로 만드는 방법은 가능. 지금은 스코프 밖.

---

## 활성 곡선 (PRD §5.2.1 v0.4)

```
b(lux) = b_min + (b_max - b_min) × clamp(log10(lux + 1) / log10(2001), 0, 1)
b_min=20, b_max=95 (UserDefaults 저장)
darkFloorLux=3 (lux ≤ 3 → b_min)

EMA: α=0.2, 1초 샘플링
  snapThreshold=50, snapDuration=3 → 3초 연속 ±50 lux면 EMA 건너뛰고 raw로 점프
  snap 발동 시 sync interval 우회하고 DDC 즉시 push
```

- 대비는 자동 조정 안 함, 고정 70 (LG HDR 4K 출하 기본값)
- 색온도는 스코프 제외 (f.lux / Night Shift 사용 안내)

---

## 현재 기본 단축키

| 액션 | 키 |
|---|---|
| Brightness Up/Down | `⌃⌥⌘ =` / `⌃⌥⌘ -` |
| Contrast Up/Down | `⌃⌥⌘ ]` / `⌃⌥⌘ [` |
| Toggle Auto | `⌃⌥⌘ B` |
| Toggle Window | `⌃⌥⌘ G` (메인 + 설정 동시 토글) |

- 설정 → Hotkeys 행 **더블클릭**으로 재할당 가능
- 재할당 시 "Clear"로 바인딩 제거도 지원 (이번 세션에서 사용자가 직접 추가)

---

## 주요 파일 맵

```
Gnomon/
├── App/
│   ├── GnomonApp.swift
│   ├── AppDelegate.swift
│   ├── StatusBarController.swift
│   └── WindowManager.swift
├── Model/
│   ├── BrightnessCurve.swift     # darkFloor 포함
│   ├── DeveloperShouts.swift     # (이번 세션에서 사용자가 추가)
│   ├── EMAFilter.swift           # snap 로직 포함
│   ├── LuxCategory.swift
│   ├── MonitorID.swift
│   ├── StringFormat.swift
│   └── WittyLabels.swift
├── Services/
│   ├── AccessibilityChecker.swift  # ← Carbon hotkey 전환 시 제거 후보
│   ├── CSVLogger.swift             # v2 스키마 + 자동 백업
│   ├── Debouncer.swift
│   ├── HotkeyManager.swift         # ← Phase 1 (Carbon) 교체 대상
│   ├── IconUpdater.swift           # 1분 tick + KST + wake notification
│   ├── LuxReader.swift             # ← Phase 3 (IOKit HID) 교체 대상
│   ├── M1DDCClient.swift           # ← Phase 2 (IOAVService 포팅) 대상
│   ├── ProcessRunner.swift
│   ├── SundialIconRenderer.swift   # 24h 시계 방향
│   └── SystemInfo.swift
├── ViewModels/
│   ├── AutoLoopController.swift    # snap 즉시 push 로직 포함
│   └── OnboardingViewModel.swift
└── Views/
    ├── AmbientSensorCard.swift
    ├── BrightnessCard.swift        # Auto 토글 황금색
    ├── ContrastCard.swift          # Reset 70 링크
    ├── MainWindow.swift
    ├── Theme.swift
    ├── WindowAccessor.swift
    ├── Onboarding/OnboardingWindow.swift
    └── Settings/
        ├── HotkeyRow.swift
        └── SettingsWindow.swift    # Min/Max Enter UX, hint 레이아웃 고정
```

**제거된 파일**: `Gnomon/Views/StatusBar.swift` (StatusBarController로 통합)

---

## 관련 문서

- [PRD.md](PRD.md) — 개발자용 명세 (v0.5)
- [BACKGROUND.md](BACKGROUND.md) — 제품 스토리 (홈페이지용)
- [research/adaptive-curves.md](research/adaptive-curves.md) — 곡선 학술 근거

---

## 새 세션 시작 멘트 예시

1. 핸드오프 문서 (이 파일) 읽음 안내
2. 사용자 의사 확인: "**Phase 1 (Carbon hotkey 교체)** 부터 시작할까?" — 가장 쉽고 리스크 낮음
3. 또는 본인이 우선순위 바꿀지 (Notarization 파이프라인 먼저 짜서 v1.3.0 바로 릴리즈하고 싶어할 수도)

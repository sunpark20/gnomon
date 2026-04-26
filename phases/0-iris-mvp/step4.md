# Step 4: views-onboarding

## 읽어야 할 파일

먼저 아래 파일들을 읽고 프로젝트의 아키텍처와 설계 의도를 파악하라:

- `/CLAUDE.md`
- `/docs/PRD.md` (사용자 여정 섹션, UI 결정 사항 — 특히 "우측 카드 레이아웃" 구조)
- `/docs/ARCHITECTURE.md` (디렉토리 구조)
- `/docs/DO_NOT_IMPLEMENT.md`

이전 step에서 생성/수정된 파일 (반드시 읽을 것):
- `/Gnomon/ViewModels/AutoLoopController.swift` (Step 3에서 전면 수정됨 — 새 프로퍼티 확인)
- `/Gnomon/Services/GammaController.swift` (Step 2)
- `/Gnomon/Services/ColorTemperature.swift` (Step 2)
- `/Gnomon/Model/DisplayID.swift` (Step 2)

기존 View 파일 (수정 대상):
- `/Gnomon/Views/MainWindow.swift`
- `/Gnomon/Views/BrightnessCard.swift`
- `/Gnomon/Views/AmbientSensorCard.swift`
- `/Gnomon/Views/Theme.swift`
- `/Gnomon/ViewModels/OnboardingViewModel.swift`
- `/Gnomon/Views/Onboarding/OnboardingWindow.swift`
- `/Gnomon/Views/Settings/SettingsWindow.swift`

## 작업

### 1. MainWindow.swift 수정

- ContrastCard 참조 제거 (Step 0에서 이미 삭제했을 수 있으나 확인)
- 우측 영역: BrightnessCard만 표시 (VStack에서 ContrastCard 줄 삭제)
- BrightnessCard가 우측 전체 공간을 차지하도록 레이아웃 조정

### 2. BrightnessCard.swift → 밝기+색온도 합친 카드

ContrastCard를 삭제한 대신, BrightnessCard 하단에 색온도 읽기 전용 슬라이더를 추가한다.

**카드 구조 (PRD 참조):**
```
┌──────────────────────────────────────┐
│ ☀ Brightness              [Auto] 토글│
│                     Sync Now  11s   │
│                                      │
│           75 %                       │
│ Min                            Max   │
│ ■■■■■■■■■■■■■■■■●──────  (수동 조절)  │
│──────────────── 중앙 경계 ────────────│
│ 3400K                        6500K   │
│ ■■■■■■■■■●─────────────  (조절 불가)  │
│ 🌡 Color Temperature          Auto   │
│  (주황 → 노랑 → 흰 → 파랑 그라데이션)  │
└──────────────────────────────────────┘
```

**밝기 섹션 (상단, 기존 유지):**
- "Brightness" 헤더 + Auto 토글
- Sync Now / Next sync 카운트다운
- 밝기 숫자 (0~100%, 탭 편집 가능)
- GoldSlider (수동 조절, auto 시 disabled)
- Min / Max 레이블은 슬라이더 **위**에 배치

**색온도 섹션 (하단, 신규):**
- 구분선 또는 시각적 경계 (Divider 또는 패딩)
- CCT 숫자 (3400K 등) — 좌측
- 6500K — 우측
- 색온도 슬라이더: **읽기 전용 커스텀 뷰**
  - 바 배경: LinearGradient — 웜(주황/앰버) → 중간(노랑/흰) → 쿨(청백)
  - Razer Chroma 스타일의 화려한 그라데이션
  - 색상 예시: `Color(red: 1.0, green: 0.6, blue: 0.2)` → `Color.white` → `Color(red: 0.7, green: 0.85, blue: 1.0)`
  - thumb 위치: `(targetCCT - 2700) / (6500 - 2700)` normalized
  - thumb은 자동으로 움직임 (사용자 드래그 불가)
  - thumb 스타일: 기존 GoldSlider와 유사한 흰 원
- 🌡 "Color Temperature" 라벨 + "Auto" 배지 (토글 아님, 텍스트만)

**밝기 슬라이더 매핑:**
- UI: 0~100 Int (사용자에게 보이는 값)
- 내부: `gamma = 0.08 + (Float(value) / 100.0) * 0.92`
- `controller.userSetBrightness(value)` 호출 시 Int 전달 (controller가 변환)

**바인딩:**
- `controller.targetCCT` — 색온도 슬라이더 thumb 위치
- `controller.targetBrightness` — 밝기 타겟 (auto 시 표시)
- `controller.lastSentBrightness` — 현재 적용된 밝기

### 3. AmbientSensorCard.swift 수정

- `monitorConnected` → `displayConnected` (프로퍼티명만 변경, DisplayID 존재 여부)
- 기존 "Disconnected" 배지 유지 (외장 모니터 미감지 시)
- CCT 정보는 BrightnessCard로 이동했으므로 여기서는 표시 안 함

### 4. OnboardingViewModel.swift 수정

- `ddcClient: M1DDCClient` → `gammaController: GammaController`
- `runDDCCheck()` → `runDisplayCheck()`:
  - `gammaController.listDisplays()` 호출
  - 외장 디스플레이 1개 이상 있는지 확인
  - `CGGetDisplayTransferByTable` 호출하여 감마 지원 확인
  - 성공: `.passed("Detected: \(name)")`
  - 실패: `.failed("No external display found. Connect an external monitor to use Century Iris.")`
- `openLunarWarningIfNeeded()` 제거 (DO_NOT_IMPLEMENT #10)
- `ddcState` → `displayState`

### 5. OnboardingWindow.swift 수정

- "Welcome to Gnomon" → "Welcome to Century Iris"
- "Detecting external monitor…" → "Checking display…"
- 모니터 설정 안내 카드 추가 (CalibrationTip 위치 재활용):
  - "💡 Tip: Set your monitor brightness to a comfortable level for bright rooms. Century Iris will dim from there automatically."
  - "If the screen looks washed out, try raising Contrast to 70-80 in your monitor's OSD menu."
- "Start Calibration" → "Start"
- Lunar 충돌 경고 관련 UI 제거

### 6. SettingsWindow.swift 수정

- Contrast 관련 단축키 행 제거 (contrastUp, contrastDown)
- HotkeyAction enum에서 `.contrastUp`, `.contrastDown` case 제거 (Step 0 또는 3에서 이미 처리됐을 수 있으나 확인)
- "Gnomon" 텍스트 → "Century Iris" (Step 0에서 이미 처리됐을 수 있으나 확인)
- 홈페이지 URL 변경 (기존 homeninja.vercel.app/#gnomon → 새 URL 또는 임시로 주석 처리)

## Acceptance Criteria

```bash
xcodegen generate && xcodebuild -scheme CenturyIris -configuration Debug build 2>&1 | tail -5
```

빌드 성공.

```bash
grep -rn "ContrastCard\|Contrast.*Manual\|userSetContrast\|ddcClient\|DDC\|Gnomon" Gnomon/Views/ Gnomon/ViewModels/OnboardingViewModel.swift | grep -v "\.swift:" | head -20
```

DDC/Gnomon/Contrast 참조 없음 (파일명 자체의 "Gnomon" 제외).

## 검증 절차

1. 위 AC 커맨드를 실행한다.
2. 앱을 실행하여 육안 확인:
   - 메인 창에 BrightnessCard + 색온도 슬라이더가 보이는가?
   - 색온도 슬라이더가 그라데이션으로 렌더되는가?
   - ContrastCard가 보이지 않는가?
   - 윈도우 타이틀이 "Century Iris"인가?
3. 온보딩 테스트:
   ```bash
   defaults write com.sunguk.centuryiris onboardingCompletedAt -float 0
   ```
   앱 재실행 후 온보딩이 뜨고, "Welcome to Century Iris"가 보이는지 확인.
4. 결과에 따라 `phases/0-iris-mvp/index.json`의 step 4를 업데이트한다.

## 금지사항

- 색온도 수동 조절 슬라이더를 만들지 마라 (DO_NOT_IMPLEMENT #8). 읽기 전용 표시만.
- ContrastCard를 다시 만들지 마라.
- 채도 조절 UI를 추가하지 마라 (DO_NOT_IMPLEMENT #3).
- 내장 디스플레이 관련 UI를 추가하지 마라 (DO_NOT_IMPLEMENT #11).
- f.lux 감지/경고 UI를 추가하지 마라 (DO_NOT_IMPLEMENT #10).
- Theme.swift의 색상 팔레트를 변경하지 마라 (색온도 그라데이션은 별도 구현).
- 기존 GoldSlider/GoldToggleStyle을 수정하지 마라. 색온도는 별도 커스텀 뷰.
- DO_NOT_IMPLEMENT.md의 항목을 구현하지 마라.

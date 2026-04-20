# 다음 세션 핸드오프

> 작성: 2026-04-20
> 이 문서는 새 Claude 세션이 컨텍스트 없이 바로 이어받을 수 있게 작성됨.

---

## TL;DR — 새 세션에서 바로 할 일

**최우선 TODO**: 사용자에게 아래 테스트 요청하고, `log.csv`를 받아서 **"찔끔찔끔" 밝기 전환 현상의 원인**을 분석한다.

1. 사용자에게 설명:
   - 현재 sync interval을 30초 → **5초로 바꿔서** 테스트해달라고 요청
   - Gnomon 설정 → Sync Options → Interval 필드에 `5` 입력
2. 테스트 프로토콜 안내:
   - 앱 실행 + 센서를 손으로 **완전히 가림** (1분 유지)
   - 다시 열어서 30초 대기
3. `~/Library/Application Support/Gnomon/log.csv` 마지막 20-30줄 받기
4. 4개 칼럼 분석:
   - `raw_lux` → macOS 센서 응답속도
   - `ema_lux` → Gnomon 내부 smoothing 출력
   - `target_brightness` → 곡선 계산 결과
   - `sent_brightness` → 실제 DDC 명령값
5. 병목 지점 찾아서 수정 제안

---

## 프로젝트 위치 / 상태

- 경로: `/Users/sunguk/0.code/moniterpicker/gnomon/`
- 최신 커밋/태그: **v1.1.7** (`adc25e9`)
- 총 커밋 18개 (Phase 0~10 + v1.1 ~ v1.1.7)
- Gate: `./Scripts/gate.sh` 4/4 통과 (lint / format / build / test)
- 테스트: 41개 (3개는 GNOMON_INTEGRATION=1 필요)

빌드:
```bash
cd /Users/sunguk/0.code/moniterpicker/gnomon
xcodegen generate  # .xcodeproj 재생성 (필요 시)
./Scripts/gate.sh  # 모든 검증 1회
# 또는 앱 실행:
xcodebuild -project Gnomon.xcodeproj -scheme Gnomon -configuration Debug -derivedDataPath build -quiet build
open build/Build/Products/Debug/Gnomon.app
```

---

## 이번 세션에서 완성된 것 (v1.1 ~ v1.1.7)

| 태그 | 내용 |
|---|---|
| v1.1 | 단축키 재할당 + 해시계 동적 아이콘 + WoW/하스 유머 70개 + 맥북 실루엣 센서 아이콘 |
| v1.1.1 | Settings를 sheet → 별도 Window scene으로 분리 + frame autosave |
| v1.1.2 | Interval을 Int → Double (소수점 OK, 상한 제거) |
| v1.1.3 | Interval 극단값(<1s, >3600s)에 위트 경고 |
| v1.1.4 | 메인 창 기본 크기 840×540 → 1000×780 |
| v1.1.5 | Settings 창 기본 크기 460×740 → 480×1080 (완전 펼침) |
| v1.1.6 | Toggle Window 핫키가 메인+설정창 동시 토글 |
| v1.1.7 | SystemInfo 수집 (macOS/모델/메모리) → `system.txt` 기록, "MacBook Sensor" → "Mac Sensor", `→ 83 tgt` → `→ 83%` |

---

## 현재 기본 단축키

| 액션 | 키 |
|---|---|
| Brightness Up/Down | `⌃⌥⌘ =` / `⌃⌥⌘ -` |
| Contrast Up/Down | `⌃⌥⌘ ]` / `⌃⌥⌘ [` |
| Toggle Auto | `⌃⌥⌘ B` |
| Toggle Window | `⌃⌥⌘ G` (메인 + 설정 동시 토글) |

- 설정 → Hotkeys 행 **더블클릭**으로 재할당 가능
- Reset to Defaults 링크로 원상복구

---

## 활성 곡선 (PRD §5.2.1 v0.4)

```
b(lux) = b_min + (b_max - b_min) × clamp(log10(lux + 1) / log10(2001), 0, 1)
b_min = 20 (기본), b_max = 95 (기본)
```

- **대비는 자동 조정 안 함**, 고정 70 (LG HDR 4K 출하 기본값)
- 색온도는 스코프 제외 (f.lux / Night Shift 사용 안내)

---

## 진단 중인 이슈 — "찔끔찔끔"

### 증상
사용자가 센서를 완전히 가렸는데, 외장 LG HDR 4K 모니터 밝기가 **한 번에 안 내려가고 약 2씩 단계적으로 감소**한다고 체감.

### 제가 실측한 것 (v1.1.7 전)
```
t=0s  AggregatedLux=537 (센서 열림)
t=6s  AggregatedLux=271 (가리기 시작)
t=8s  AggregatedLux=0.99 (완전 가림)
```

→ macOS의 `AggregatedLux`는 **4초 내** 거의 0까지 떨어짐 (충분히 빠름).

### 이론 (30초 interval + α=0.2 EMA)
센서 가리면 30초 후 EMA는 거의 0으로 수렴 → target = b_min (20%)
→ **DDC는 한 번에 82 → 20 명령 전송**해야 정상
→ 만약 LG 모니터 OSD가 **자체적으로 부드럽게 애니메이션** 하면 사용자 눈엔 "찔끔찔끔"으로 보일 수 있음

### 3가지 가설
1. **LG HDR 4K OSD의 내부 smoothing** (하드웨어, Gnomon 탓 아님)
2. **실제로 target이 단계적으로 떨어짐** (예상과 다름, 버그 가능성)
3. **m1ddc 경합** (다른 디스플레이 앱 동시 실행 중)

### 분석 방법
v1.1.7의 `log.csv`에 다음 칼럼 기록됨:
```
timestamp, raw_lux, ema_lux, target_brightness, sent_brightness, contrast, auto_on, manual_override
```

5초 interval로 세팅 후 한 바퀴 돌면 각 칼럼 시계열 관찰로 **병목 지점 즉시 판별 가능**.

### 받아야 할 데이터
1. `~/Library/Application Support/Gnomon/log.csv` (마지막 20-30줄)
2. `~/Library/Application Support/Gnomon/system.txt` (전체)

---

## 잠재적 개선 방향 (이슈 분석 후 결정)

가정: target이 단계적으로 떨어지는 게 확인되면 ↓

### 옵션 A — EMA 약화/제거
- 현재 α=0.2 → 0.5 또는 1.0 (즉, 스무딩 완전히 끔)
- 장점: 반응성 ↑
- 단점: 잠깐의 조도 튕김(사람 지나감 등)에 반응

### 옵션 B — Raw lux 사용
- `AggregatedLux` 대신 `Lux1`/`Lux2` 직접 사용
- 장점: macOS의 pre-smoothing도 우회
- 단점: 센서 노이즈에 더 민감

### 옵션 C — Big-delta snap
- `abs(target - lastSent) >= 10`이면 EMA 건너뛰고 raw 즉시 적용
- 장점: 급격한 변화는 빠르게, 미세 변화는 부드럽게
- 단점: 로직 복잡

### 옵션 D — LG 모니터 고유 동작
- 하드웨어 OSD smoothing이면 Gnomon 쪽 수정 불필요
- 사용자에게 "모니터 설정에서 Response Time 또는 Brightness Transition 끄기" 안내

로그 분석 전까진 결론 X.

---

## 주요 파일 맵

```
Gnomon/
├── App/
│   ├── GnomonApp.swift           # @main, WindowGroup + Settings Window scene
│   ├── AppDelegate.swift         # 메뉴바 + IconUpdater 연결
│   ├── StatusBarController.swift # NSStatusItem (메뉴바 아이콘)
│   └── WindowManager.swift       # 메인/설정 창 동시 토글
├── Model/
│   ├── BrightnessCurve.swift     # 곡선 공식
│   ├── EMAFilter.swift           # α=0.2 스무딩
│   ├── LuxCategory.swift         # 7구간 분류
│   ├── MonitorID.swift           # m1ddc 디스플레이 ID
│   ├── StringFormat.swift        # "30.00" → "30" 헬퍼
│   └── WittyLabels.swift         # WoW/하스 유머 70개
├── Services/
│   ├── AccessibilityChecker.swift
│   ├── CSVLogger.swift           # log.csv + system.txt 기록
│   ├── Debouncer.swift           # 200ms 슬라이더 debounce
│   ├── HotkeyManager.swift       # 글로벌 핫키 (재할당 가능)
│   ├── IconUpdater.swift         # 매시간 해시계 아이콘 갱신
│   ├── LuxReader.swift           # corebrightnessdiag 래퍼
│   ├── M1DDCClient.swift         # m1ddc 래퍼
│   ├── ProcessRunner.swift       # Foundation.Process async 래퍼
│   ├── SundialIconRenderer.swift # Core Graphics 해시계 그리기
│   └── SystemInfo.swift          # 시스템 정보 수집 (v1.1.7+)
├── ViewModels/
│   ├── AutoLoopController.swift  # @Observable 중앙 상태
│   └── OnboardingViewModel.swift
└── Views/
    ├── AmbientSensorCard.swift   # "Mac Sensor" 카드
    ├── BrightnessCard.swift      # @Bindable 컨트롤
    ├── ContrastCard.swift        # @Bindable 컨트롤
    ├── ContentView.swift         # (삭제됨 — MainWindow가 대체)
    ├── MainWindow.swift          # 전체 레이아웃
    ├── StatusBar.swift           # Pause/Apply/Countdown
    ├── Theme.swift               # 베이지+골드 팔레트
    ├── WindowAccessor.swift      # NSWindow 브릿지 + FrameAutosave
    ├── Onboarding/OnboardingWindow.swift
    └── Settings/SettingsWindow.swift
```

---

## 관련 문서

- [PRD.md](PRD.md) — 개발자용 명세 (v0.5)
- [BACKGROUND.md](BACKGROUND.md) — 제품 스토리 (홈페이지용)
- [research/adaptive-curves.md](research/adaptive-curves.md) — 곡선 학술 근거 5,000단어

---

## 새 세션 시작 멘트 예시

사용자가 "새 세션에서 바로 todo 하라고" 했으니, 첫 응답으로 다음 내용을 정리해서 전달:

1. 핸드오프 문서 읽음 안내
2. **5초 interval 테스트 즉시 요청** (위 "TL;DR" 프로토콜 그대로)
3. `log.csv` + `system.txt` 받으면 바로 분석 착수 가능하다고 고지

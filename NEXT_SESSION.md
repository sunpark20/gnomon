# 다음 세션 핸드오프

> 작성: 2026-04-26 (세션 6 — Century Iris PoC + 리서치 + 하네스 설계)
> 업데이트: 2026-05-20 (Gnomon 1.7.2 DDC sleep/wake hotfix)
> 이 문서 하나만으로 새 세션이 컨텍스트 없이 이어받을 수 있게 작성됨.

---

## 2026-05-20 Hotfix Notes — Gnomon 1.7.2

현재 checkout은 아직 Century Iris 전환 전의 DDC 기반 Gnomon이다. 이번 hotfix는 사용자가 MacBook을 잠자기에서 깨우고 외장 모니터가 다시 붙은 뒤, DDC write가 성공처럼 보이지만 실제 밝기가 바뀌지 않는 상태를 다룬다.

- 메인 창 타이틀은 `Gnomon 1.7.2`처럼 `CFBundleShortVersionString`을 포함한다.
- `AutoLoopController`는 brightness write 후 read-back으로 실제 적용 여부를 검증한다.
- read-back mismatch 또는 DDC 실패 시 모니터를 재탐색하고 1회 재시도한다.
- 재시도 후에도 실패하면 `activeMonitor = nil`로 내려 UI가 disconnected 상태를 표시하게 한다.
- Auto/manual brightness 모두 `activeMonitor`가 없으면 write 전에 재탐색한다.
- wake/display-change 복구 지연은 `0s, 3s, 8s, 20s, 60s`다.
- `initialSyncTask`는 cancel 후 sleep이 풀렸을 때 추가 sync를 실행하지 않도록 `Task.isCancelled`를 확인한다.

변경 파일:
- `Gnomon/App/GnomonApp.swift`
- `Gnomon/ViewModels/AutoLoopController.swift`
- `GnomonTests/AutoLoopControllerTests.swift`

검증:
- `swiftformat --lint .` passed.
- `swiftlint --strict --quiet` passed.
- `xcodebuild -project Gnomon.xcodeproj -scheme Gnomon -configuration Debug -derivedDataPath /private/tmp/gnomon-derived-test PRODUCT_BUNDLE_IDENTIFIER=com.sunguk.gnomon.GnomonTestHost test` passed: 56 tests, 3 hardware integration tests skipped.
- Plain `xcodebuild ... test` can fail while the released Gnomon is running because the app's single-instance guard sees the same bundle identifier. Use the temporary test bundle identifier above, or quit the running app first.

---

## TL;DR — 새 세션에서 바로 할 일

**하네스 실행: `python3 scripts/execute.py 0-iris-mvp`**

Step 파일 6개가 이미 작성되어 있다. 실행하면 Gnomon → Century Iris 전환이 자율적으로 진행된다. 중간 확인 없이 끝까지 실행된다. 실패 시 최대 3회 자가 교정.

실행 전 확인: `phases/0-iris-mvp/index.json`에서 모든 step이 `pending`인지 확인.

---

## 프로젝트 현재 상태

- 경로: `/Users/sunguk/0.code/0.shipping/gnomon` (Gnomon → Century Iris 전환 준비 중)
- 브랜치: `main`
- 최신 릴리즈: `v1.7.2`
- 2026-05-20 기준 위 hotfix는 `v1.7.2`에 포함됨.
- 빌드: Gnomon으로는 빌드 가능. Century Iris 전환은 아직 미시작.
- **하네스 상태**: Step 파일 작성 완료, 실행 대기 (Phase C → D 전환점)

---

## 이번 세션 성과 (세션 6)

| 항목 | 내용 |
|---|---|
| **PoC 검증** | 조도센서 IORegistry 읽기 sandbox 동작 확인 (4040/4040, 100%), 감마 디밍 sandbox 동작 확인. `PoC/main.swift` |
| **알고리즘 리서치** | Kelvin→RGB (Tanner Helland), 통합 감마 테이블 공식, Lux→밝기/CCT 매핑, 멜라토닌 보호 공식. `research/software-dimming-algorithms.md` |
| **오픈소스 조사** | MonitorControl(33K), Lunar(5.5K), OpenDisplay(MIT) 등 감마/센서 구현 참고 소스 확보 |
| **학술 논문 검증** | Choi&Suk 2014 (CCT 공식), Kim 2018 (밝기 데이터), Gimenez 2022 (멜라토닌) — Semantic Scholar 인용 검증 |
| **제품 결정** | 밝기+색온도 2개만, 캘리브레이션 제거, 명암은 모니터 OSD, 내장 디스플레이 미지원, 감마 fade 넣기, 오버레이 fallback 안 함 |
| **하네스 설계** | CLAUDE.md, PRD(상수/에러/UX 여정), ARCHITECTURE(데이터 흐름/상태), ADR(11개), DO_NOT_IMPLEMENT(13개) 작성. Step 파일 6개 작성 완료 |
| **App Store 메타데이터** | `appstore/metadata.md` (Century Iris, com.sunguk.centuryiris) |
| **스킬 개선** | su-end 트리거 조건 완화 (명시적 호출만), su-harness에 금지 목록(A+ 단계) 추가 |

---

## 미완료 TODO (우선순위 순)

### 1. ⭐⭐⭐ 하네스 실행 (예상: 1~2시간)

**명령어:** `python3 scripts/execute.py 0-iris-mvp`

6개 step이 순차 자율 실행된다:
- Step 0: project-setup (번들 ID, sandbox, DDC 파일 삭제)
- Step 1: lux-reader (subprocess → IORegistry)
- Step 2: gamma-service (GammaController, ColorTemperature, DisplayID 신규)
- Step 3: auto-loop (AutoLoopController DDC→감마 전환)
- Step 4: views-onboarding (UI 수정, 밝기+색온도 합친 카드)
- Step 5: test-verify (테스트 + 빌드 검증)

**관련 파일**: `phases/0-iris-mvp/step0.md` ~ `step5.md`

### 2. ⭐⭐ 하네스 완료 후 수동 검증 (예상: 30분)

하네스 실행 후 앱을 직접 실행하여 확인:
- 감마 디밍이 외장 모니터에서 동작하는가?
- 색온도 슬라이더가 그라데이션으로 자동 움직이는가?
- 슬라이더 수동 조절 → Auto OFF → 토글 복귀가 되는가?
- 온보딩이 Century Iris 이름으로 뜨는가?
- 앱 종료 시 감마가 복원되는가?

### 3. ⭐ App Store 제출 준비 (예상: 1일)

- 스크린샷 촬영
- App Store Connect 설정
- 심사 제출

---

## 핵심 제품 결정 (확정됨, 변경 시 docs/ 수정 필요)

| 결정 | 내용 |
|---|---|
| 밝기 제어 | 감마 테이블 (0.08~1.0), 수동+자동 |
| 색온도 | Kruithof + Tanner Helland, 항상 자동, 읽기 전용 표시 |
| 캘리브레이션 | 없음 |
| 명암 | 모니터 OSD로 사용자 직접 |
| 내장 디스플레이 | 미지원 (외장 모니터 전용) |
| 오버레이 fallback | 안 함 (감마만) |
| f.lux 충돌 | 사용자에게 맡김 |
| 감마 fade | 넣음 (~500ms, 30단계) |
| 앱 아이콘 | 기존 Gnomon 재사용 |
| UI | 밝기(위)+색온도(아래) 합친 카드, Razer 스타일 CCT 그라데이션 |

---

## 주요 파일 맵

```
CLAUDE.md                          # 프로젝트 규칙 (Century Iris)
docs/
├── PRD.md                         # 제품 요구사항 (UX 여정, 에러 19건, 상수 17개)
├── ARCHITECTURE.md                # 아키텍처 (데이터 흐름, 상태, 패턴)
├── ADR.md                         # 기술 결정 (11개 ADR)
├── DO_NOT_IMPLEMENT.md            # 금지 목록 (13개)
└── UI_GUIDE.md                    # UI 가이드 (미작성)

phases/
├── index.json                     # phase 현황
└── 0-iris-mvp/
    ├── index.json                 # step 현황 (6개 pending)
    ├── step0.md ~ step5.md        # step 실행 지시서

scripts/execute.py                 # 하네스 실행 엔진

PoC/main.swift                     # 동작 확인된 센서+감마 코드
appstore/metadata.md               # App Store 메타데이터
research/software-dimming-algorithms.md  # 공식 + 학술 출처
```

---

## 관련 문서

- [docs/PRD.md](docs/PRD.md) — 제품 요구사항
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — 아키텍처
- [docs/ADR.md](docs/ADR.md) — 기술 결정 기록
- [docs/DO_NOT_IMPLEMENT.md](docs/DO_NOT_IMPLEMENT.md) — 금지 목록
- [research/software-dimming-algorithms.md](research/software-dimming-algorithms.md) — 감마/CCT 공식
- [appstore/metadata.md](appstore/metadata.md) — App Store 메타데이터

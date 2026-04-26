# 다음 세션 핸드오프

> 작성: 2026-04-26 (세션 6 — Century Iris PoC + 리서치 + 하네스 설계)
> 이 문서 하나만으로 새 세션이 컨텍스트 없이 이어받을 수 있게 작성됨.

---

## TL;DR — 새 세션에서 바로 할 일

**하네스 실행: `python3 scripts/execute.py 0-iris-mvp`**

Step 파일 6개가 이미 작성되어 있다. 실행하면 Gnomon → Century Iris 전환이 자율적으로 진행된다. 중간 확인 없이 끝까지 실행된다. 실패 시 최대 3회 자가 교정.

실행 전 확인: `phases/0-iris-mvp/index.json`에서 모든 step이 `pending`인지 확인.

---

## 프로젝트 현재 상태

- 경로: `/Users/sunguk/0.code/gnomoniter` (Gnomon 카피본 → Century Iris로 전환 중)
- 브랜치: `main`
- 최신 커밋: `eded073` (push 완료)
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

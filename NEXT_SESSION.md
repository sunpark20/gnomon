# 다음 세션 핸드오프

> 작성: 2026-04-26 (세션 6 — Century Iris PoC + 리서치)
> 이 문서 하나만으로 새 세션이 컨텍스트 없이 이어받을 수 있게 작성됨.

---

## TL;DR — 새 세션에서 바로 할 일

**`/su-harness`로 Century Iris 구현 시작.** Gnomon → Century Iris 전환 (DDC→감마, subprocess→IORegistry, sandbox 적용). 이번 세션에서 PoC 검증 + 알고리즘 리서치 + 제품 결정 완료. 하네스 설계부터 시작.

---

## 프로젝트 현재 상태

- 경로: `/Users/sunguk/0.code/gnomoniter` (Gnomon 코드 카피본, 여기서 Century Iris로 전환)
- 브랜치: `main`
- **이 리포는 Gnomon 원본이 아닌 카피본.** Century Iris 새 프로젝트로 사용.
- 번들 ID: `com.sunguk.centuryiris` (변경 예정)
- 앱 이름: **Century Iris**
- 부제(한국어): 외장 모니터 자동 밝기 조절
- 부제(영어): Auto Monitor Brightness

---

## 이번 세션 성과 (세션 6)

| 항목 | 내용 |
|---|---|
| **PoC 검증** | 조도센서 IORegistry 읽기 sandbox 동작 확인 (4040/4040, 100%), 감마 디밍 sandbox 동작 확인. `PoC/main.swift` |
| **알고리즘 리서치** | Kelvin→RGB (Tanner Helland), 통합 감마 테이블 공식, Lux→밝기/CCT 매핑, 멜라토닌 보호 공식. `research/software-dimming-algorithms.md` |
| **오픈소스 조사** | MonitorControl(33K), Lunar(5.5K), OpenDisplay(MIT) 등 감마/센서 구현 참고 소스 확보 |
| **학술 논문 검증** | Choi&Suk 2014 (CCT 공식), Kim 2018 (밝기 데이터), Gimenez 2022 (멜라토닌) — Semantic Scholar로 인용 검증 |
| **제품 결정** | 밝기+색온도 2개만 (채도/명암 제외), 캘리브레이션 제거, 명암은 모니터 OSD로 사용자 직접 |
| **App Store 메타데이터** | `appstore/metadata.md` 생성 (이름, 부제, 한/영 설명, 키워드, 심사 메모) |
| **배경 문서** | `bgraw.md`, `bgwiki.md` 갱신 (DDC vs 감마 비교, 캘리브레이션 방법, 파라미터 확정, 캘리브레이션 제거) |

---

## 미완료 TODO (우선순위 순)

### 1. ⭐⭐⭐ Century Iris 구현 — /su-harness로 진행 (예상: 1~2주)

사용자가 하네스 방식으로 진행하겠다고 결정. 하네스 설계부터 시작.

**주요 구현 단계:**

| # | 작업 | 핵심 파일 |
|---|---|---|
| 1 | LuxReader 교체 (subprocess→IORegistry) | `Gnomon/Services/LuxReader.swift` |
| 2 | DDC→GammaController 교체 | `Gnomon/Services/NativeDDC.swift`, `M1DDCClient.swift` → 새 GammaController |
| 3 | 색온도 추가 (Tanner Helland + Kruithof) | 새 파일 또는 GammaController 내 |
| 4 | Sandbox 적용 | `Entitlements.plist`, `project.yml` |
| 5 | UI 수정 | Contrast 카드 제거, CCT 표시 추가, 온보딩 변경 |
| 6 | 번들 ID/이름 변경 | `project.yml`, `Info.plist` |
| 7 | 테스트 | 외장 모니터, Night Shift 충돌, crash recovery |
| 8 | App Store 제출 | 스크린샷, 메타데이터, 심사 |

**핵심 결정 사항 (이미 확정):**
- 밝기: Gnomon 로그 곡선 재사용, 캘리브레이션 없음
- 색온도: Kruithof 테이블 (lux→CCT) + Tanner Helland (CCT→RGB)
- 명암: 모니터 OSD (사용자 직접, 온보딩 안내만)
- 채도: 건드리지 않음
- 감마 최소값: 0.08 (완전 검정 방지)

**참조 문서:**
- `research/software-dimming-algorithms.md` — 모든 공식과 출처
- `appstore/metadata.md` — App Store 메타데이터
- `PoC/main.swift` — 동작 확인된 센서+감마 코드

---

## 핵심 기술 참조

### 조도센서 (IORegistry, sandbox 동작 확인됨)
```swift
IOServiceMatching("IOMobileFramebufferShim")
IORegistryEntryCreateCFProperty(service, "AmbientBrightness", ...)
lux = Double(raw) / 65536.0
```

### 감마 디밍 (CGSetDisplayTransferByTable, sandbox 동작 확인됨)
```swift
CGGetDisplayTransferByTable(displayID, 256, &origR, &origG, &origB, &count)
let scaled = orig.map { $0 * factor }
CGSetDisplayTransferByTable(displayID, count, scaledR, scaledG, scaledB)
CGDisplayRestoreColorSyncSettings()  // 복원
```

### 통합 감마 테이블 (밝기 + 색온도)
```swift
let (rMul, gMul, bMul) = kelvinToRGB(temperature)
for i in 0..<256 {
    let v = Float(i) / 255.0
    r[i] = clamp(v * brightness * rMul)
    g[i] = clamp(v * brightness * gMul)
    b[i] = clamp(v * brightness * bMul)
}
```

---

## 주요 파일 맵

```
PoC/                               # PoC 코드 (sandbox 검증 완료)
├── main.swift                     # 센서+감마 PoC 앱
├── Entitlements.plist             # com.apple.security.app-sandbox
├── Info.plist
└── build_and_run.sh

appstore/
└── metadata.md                    # Century Iris App Store 메타데이터

research/
├── adaptive-curves.md             # Gnomon 기존 곡선 학술 근거
└── software-dimming-algorithms.md # 감마/CCT/멜라토닌 공식 + 출처

Gnomon/Services/                   # 교체 대상
├── NativeDDC.swift                # 제거 → GammaController
├── M1DDCClient.swift              # 제거 → GammaController
└── LuxReader.swift                # subprocess → IORegistry
```

---

## 관련 문서

- [research/software-dimming-algorithms.md](research/software-dimming-algorithms.md) — 감마/CCT/멜라토닌 공식 전체
- [research/adaptive-curves.md](research/adaptive-curves.md) — 밝기 곡선 학술 근거
- [appstore/metadata.md](appstore/metadata.md) — App Store 메타데이터
- [bgraw.md](bgraw.md) — 배경 원문 기록
- [bgwiki.md](bgwiki.md) — 배경 정제본

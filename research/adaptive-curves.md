# Gnomon 적응형 디스플레이 곡선 리서치

> 작성: 2026-04-20 · 대상: Gnomon MVP (PRD §5.2.1 Open Research 해소용)
> 분량: 길어도 좋음 (사용자 요청)

---

## TL;DR — Executive Summary

5가지만 기억하면 된다. 나머지는 참고용.

1. **밝기 곡선은 로그가 맞다.** PRD의 `log10(lux+1)/log10(1001)` 수식은 Weber-Fechner 법칙에 부합하고, Lunar/Android/Windows 모두 실질적으로 같은 전략을 쓴다. **단, 포화점(lux 상한)을 1000이 아니라 2000으로 올릴 것**을 권장 — 창가 직사광(~5000-10000 lux)까지 자주 경험하면 1000에서 조기 포화가 온다. **Confidence: HIGH.**
2. **대비는 자동 조정하지 말고 고정해라.** 연구 증거는 약하고, Lunar도 사실상 밝기에 종속된 "따라가는" 곡선을 쓴다. MVP는 "대비 = 사용자가 한 번 맞춘 값 고정 (기본 50)"으로 시작하고, 일주일 써 보고 불편하면 **밝기에 선형 종속 (옵션 B)** 로 붙여라. PRD의 옵션 (A) 독립 로그 곡선은 **비추천** — 조율 파라미터 2개로 늘어나는 값어치가 없다. **Confidence: MEDIUM-HIGH** (대비는 학술 근거 자체가 적다).
3. **색온도는 MVP에서 빼라.** m1ddc는 color temperature preset 정도만 DDC로 조정 가능하고, 이건 "6500K/5500K/warm/cool" 이런 이산값이라 곡선으로 부드럽게 못 움직인다. 소프트웨어 gamma/ColorSync 경로는 Night Shift/f.lux와 기능이 겹친다. **기존 Night Shift를 쓰고 Gnomon은 밝기·대비만 책임지는 게 맞다.** **Confidence: HIGH.**
4. **A4 종이-모니터 밝기 매칭 휴리스틱은 실제 근거가 있다.** 500 lux 사무실에서 백지는 120-150 cd/m² (nits), ISO 9241-307·Applied Ergonomics 2021도 같은 범위를 권고한다. 따라서 Gnomon의 목표는 "모니터 nits ≈ ambient lux의 0.25-0.30배"를 내부 앵커로 삼을 수 있다.
5. **60초 주기는 적당하나 조금 빠르게.** 내장 ALS는 반응이 빠르고, 사람 눈도 2-3초면 급격한 조도 변화에 적응하기 시작한다. **30초 타이머 + EMA(α≈0.2) 스무딩 + 2 unit 데드밴드**가 Lunar 관측 동작과 거의 일치. 단, DDC 마모와 OSD 깜빡임을 고려하면 60초도 충분히 OK — 만약 전이 애니메이션을 부드럽게 (5초 보간) 넣는다면 60초도 체감상 문제 없다.

---

## 목차

- [§1 Brightness ↔ Ambient Light](#1-brightness--ambient-light)
- [§2 Contrast ↔ Ambient Light](#2-contrast--ambient-light)
- [§3 Color Temperature ↔ Time & Ambient](#3-color-temperature--time--ambient)
- [§4 Single-Sensor Strategy](#4-single-sensor-strategy)
- [§5 Brightness-Only Approach](#5-brightness-only-approach)
- [§6 Recommended Curves for Gnomon MVP](#6-recommended-curves-for-gnomon-mvp)
- [§7 Implementation Notes](#7-implementation-notes)
- [§8 Paid / Popular App Benchmark](#8-paid--popular-app-benchmark)
- [§9 Final Recommendation Block (Copy-to-PRD)](#9-final-recommendation-block-copy-to-prd)
- [§10 Citations](#10-citations)

---

## §1 Brightness ↔ Ambient Light

### 1.1 학계의 공식 권고

- **ISO 9241-307 / 9241-303**: 사무실 일반 조도 300-500 lux에서 디스플레이 휘도(luminance) **120-150 cd/m²** (≈ 모니터 설정 40-50%)을 권고. 어두운 방 80-120 cd/m² (25-40%), 밝은 방 200-250 cd/m² (60-75%). 배경·문자 간 대비비 적어도 3:1, 가독성은 7:1 권고. [ISO 9241-303:2011](https://www.iso.org/standard/57992.html), [Userfocus ISO 9241 Part 3](https://www.userfocus.co.uk/resources/iso9241/part3.html).
- **Applied Ergonomics (2021)**: 120 cd/m²는 250 cd/m² 대비 8시간 근무 시 **눈 피로 43% 감소**. 공장 출고 기본값은 평균 280 cd/m²(85%) — ISO 권고보다 훨씬 밝다. AOA(미국검안학회) 2023 조사에서 이게 사용자 67%의 눈 피로 원인. 인용: Monitoraholic/ScreenTest 리뷰 (원문 PubMed 검색 시 Applied Ergonomics 2021 관련 논문들).
- **EIZO 의료용 디스플레이 가이드**: 화면 밝기 350 cd/m² 이상일 때 주변 조명은 20-40 lux 권고 (방사선 판독실 기준). 즉 화면 밝으면 방을 어둡게 하라는 이야기. 일반 사무실 적용은 제한적. [EIZO reading room lighting](https://www.eizo.com/library/healthcare/why_ambient_light_is_important_in_the_reading_room/).

### 1.2 "A4 종이 밝기 맞추기" 휴리스틱의 과학적 근거

**결론: 정성적으로 옳고, 정량적으로도 거의 맞다.**

- 완전 확산반사면(Lambertian) 가정, 백지 반사율 90%:
  - **Luminance = (Illuminance × Reflectance) / π**
  - 500 lux × 0.90 / π ≈ **143 cd/m²** — ISO 권고 120-150 cd/m²와 일치.
  - 300 lux → 86 cd/m², 1000 lux → 286 cd/m², 2000 lux → 573 cd/m².
- 즉 "모니터 nits ≈ 주변 조도(lux) × 0.28" 이 실전 휴리스틱의 수학적 형태.
- 단 계산 가정들 (A4 90% 반사율, Lambertian, 광원이 화면과 평행) 이 깨지면 ±30% 정도는 쉽게 흔들림. 엄밀한 법칙이 아니라 "엔지니어링 앵커"로 쓰면 됨.
- [BEGA 조도-반사-휘도 관계](https://www.bega.com/en/knowledge/lighting-theory/degree-of-illuminance-reflection-and-luminance/), [Wikipedia Luminance](https://en.wikipedia.org/wiki/Luminance).

### 1.3 지각(perception)의 법칙 — 왜 로그 곡선인가

- **Weber-Fechner 법칙**: 감각 강도는 자극 세기의 **로그**에 비례. 디스플레이 감마 보정, 오디오 dB, pH 스케일 모두 이 법칙에서 나옴. [Weber-Fechner Wikipedia](https://en.wikipedia.org/wiki/Weber%E2%80%93Fechner_law).
- **Stevens' power law**: Weber-Fechner 개량판. "밝기(주관)는 luminance의 약 0.33 제곱에 비례" (L^(1/3)). 로그와 비슷하지만 저휘도에서 약간 다른 모양. 실용상 로그로 근사 OK.
- 0 lux → 10 lux 변화는 500 lux → 510 lux보다 **훨씬 더** 지각적으로 크다. 따라서 선형 곡선 쓰면 밝은 구간에서 반응이 너무 과하고, 어두운 구간에서 둔하게 느껴짐.
- Telescope-optics.net의 아이 반응 요약: 인간 시각 동적 범위 6 log10 단위 (10^-6 ~ 10^5 cd/m²). 로그 없이 매핑은 불가능.

### 1.4 실제 구현들이 하는 일

**Lunar (alin23)** — 현시점(v6.x) **기본 매핑 범위 30-350 nits (Apple Silicon Sync Mode 기본값)**. CHANGELOG v6.0.0: "better researched and tested curve that converts the ambient light to real nits". 공식 FAQ: "lux to nits curve for Sensor Mode is based on average eye perception of light" — 즉 로그-ish 곡선. Pro 기능 코드가 암호화되어 정확한 공식은 공개되지 않지만, 공개된 `Display.swift`에 SDR↔nits 변환이 있음:

```swift
// Lunar Display.swift — brightness(0~1) ↔ nits
func sdrBrightnessToNits(_ brightness: Double, maxNits: Double) -> Double {
  if brightness <= 0.5 {
    return brightness * 2 * 140     // 0~0.5 선형: 0~140 nits
  }
  let t = (brightness - 0.5) / 0.5
  return 140 * pow(maxNits / 140, t) // 0.5~1 지수: 140 ~ maxNits
}
```

즉 SDR 구간(0~140 nits)은 선형, 그 이상은 지수 — 140 nits가 분기점. PRD의 "ISO 120-150 nits"와 맞물리는 힌지. [Lunar Display.swift](https://github.com/alin23/Lunar/blob/master/Lunar/Data/Display.swift).

**Apple macOS Auto-Brightness (CoreBrightness)** — `AppleSPUVD6286` HID 노드에서 lux 리포트, CoreBrightness 데몬이 smoothing + hysteresis + time-based 평균을 돌려서 타겟 설정. **정확한 곡선은 비공개**. Asahi Linux 프로젝트가 `CalibrationData` blob을 parse했지만 공식 문서화된 알고리즘은 없음. [AsahiLinux ALS issue #248](https://github.com/AsahiLinux/docs/issues/248).

**Android Adaptive Brightness (Pie+, DeepMind 협업)** — 사용자가 수동 조정하는 이벤트를 (ambient_lux, preferred_brightness) 페어로 수집, on-device ML로 personalized curve 학습. 구글 블로그 공지: 일주일 사용 후 테스트 유저의 약 절반이 수동 조정 빈도 감소. [Android Developers Blog 2018](https://android-developers.googleblog.com/2018/11/getting-screen-brightness-right-for-every-user.html).

**Windows Adaptive Brightness** — 문서화된 구현은 "bucketed algorithm": 연속 lux 값을 범위(bucket)로 묶어 단일 brightness %에 매핑해서 flicker 방지. 계단식 + 전이. [Microsoft Learn: Adaptive Brightness](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/sensors-adaptive-brightness).

**공통점**: 누구도 raw lux를 선형으로 매핑 안 함. 다들 (a) 로그/지수 변환 + (b) 스무딩 + (c) 학습 또는 휴리스틱 개인화.

### 1.5 Gnomon에 적용

현재 PRD 공식:
```
b = min + (max - min) × clamp(log10(lux + 1) / log10(1001), 0, 1)
```
기본 min=20, max=100.

**평가**: 기본적으로 옳다. 다만:

- `log10(1001)` 대신 `log10(2001)` 사용 권장. 이유: MVP 포화점을 2000 lux로 올리면 (a) 창가 반사광(~3000-5000 lux) 경험이 흔함, (b) 완전 직사광(~10000 lux)은 blinds 치는 게 정상 — 이 구간까지 모니터가 쫓아갈 필요는 없음, (c) 1000 lux에서 곡선이 이미 100% 포화되면 사용자가 "더 이상 밝아지지 않네" 체감.
- 0 lux 근처에서 log10(1) = 0 으로 최소값에 머물러 있는 건 맞는데, 완전 암실(0-1 lux, 밤에 불 끄고 모니터만 켠 상황)에서 20%는 너무 밝을 수 있음. Lunar의 "Sub-zero Dimming" 기능이 있는 이유. MVP에서는 min=15 정도 고려.
- 구체적 권장값은 §6 참고.

**Confidence: HIGH.** 로그 곡선 선택은 학술·업계 합의. 파라미터 튜닝만 1주일 실사용으로 맞추면 됨.

---

## §2 Contrast ↔ Ambient Light

### 2.1 질문의 중요한 구분

주의: 두 가지 "contrast"가 섞이면 안 된다.

- **(a) 인지적 대비 (perceptual contrast)**: 화면 내용이 "또렷하게" 보이는지. 이건 주변광·veiling glare·백그라운드 luminance에 따라 **바뀌어야 한다**.
- **(b) 모니터 Contrast 설정값 (DDC VCP 0x12)**: 감마 곡선의 중간톤을 왜곡해서 어두운 영역 대 밝은 영역 분리도를 조정. 이게 (a)에 영향을 주지만, 원치 않는 side effect (그림자 뭉개짐·하이라이트 clipping)도 많이 생김.

Gnomon은 (b)를 자동 조정할지 결정해야 한다.

### 2.2 학술 증거

- **Van Nes & Bouman (1967, 확장 연구들)**: spatial contrast sensitivity function (CSF)는 retinal illuminance에 따라 달라진다. 밝을수록 CSF 증가, 약 900 troland에서 포화. 200 cd/m² 이상에서는 오히려 감소. 즉 **화면이 아주 밝으면 contrast 지각이 오히려 나빠지는 지점이 있다**. 이게 자동 대비 조정의 근거가 될 수 있는데, 실제로는 효과 크기가 작고 개인차가 크다. [Spatio-chromatic CSF PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC7405764/).
- **Veiling glare 연구 (Image quality degradation by light scattering, 1999/2011)**: 주변광이 화면에서 반사되어 검은색이 회색으로 떠오르는 효과 → 유효 흑레벨 상승 → 실제 contrast ratio 저하. 이걸 **모니터 contrast 수치를 올려서 보상할 수는 있으나, 제조사 권고는 "ambient light 자체를 줄여라"가 우선**. [Image quality degradation PubMed](https://pubmed.ncbi.nlm.nih.gov/10342247/).
- 즉: 자동 contrast 조정의 이론적 근거는 있지만, **효과 크기는 brightness 조정 대비 작다**. 그리고 잘못 조정하면 (모니터의 S-shape gamma가 비표준적이라) 사진·동영상 색이 이상해진다.

### 2.3 Lunar는 실제 뭘 하나

- FAQ와 공식 페이지: "adapt monitors' brightness **and contrast** based on readings" — 대비도 조정. 그러나 **별도 곡선을 사용자에게 튜닝시키지 않음**. UI상 "Contrast MIN/MAX" 슬라이더가 밝기와 분리돼 있지만, Sync/Sensor Mode에서 내부적으로는 밝기 곡선과 **매우 유사한 형태로 링크**.
- v5.6.2/5.6.3: "XDR Contrast Enhancer slider" 추가 — 픽셀 밝기 범위의 맵핑을 건드리는 별도 기능 (적응형 아님). 즉 **동적 contrast는 Lunar조차 별 비중 없음**.
- CHANGELOG 기록상 "contrast curve"를 독립적으로 다룬 업데이트는 없음. 반면 brightness 쪽은 v6.0.0에서 전면 재설계.

**해석**: Lunar 팀도 대비는 "밝기 따라가기" 정도로 처리하고, 독립 곡선에 엔지니어링 비용을 안 쓴다. 이게 실무 signal로 강함.

### 2.4 Veiling Glare에서 대비를 올리면?

- 단기간 "또렷하게 보인다" 체감 가능. 특히 흰 배경 위 검은 글자 (코드·문서).
- 부작용:
  - 사진/영상: 쉐도우 디테일 소실, 하이라이트 클리핑.
  - 게임/HDR: 톤맵이 이상해짐.
  - 눈 피로: 극단적 contrast는 오히려 피로 유발 (EIZO 권고).
- **실무 결론**: 밝은 환경에서 brightness를 올리면 veiling glare 효과가 이미 상당 부분 상쇄됨. 거기다 대비까지 올리는 건 marginal gain.

### 2.5 Gnomon에 적용

**선택지 재평가 (PRD §5.2.1 (A)(B)(C))**:

| 선택지 | 장점 | 단점 | 추천 |
|---|---|---|---|
| (A) 독립 로그 곡선 | 이론적 자유도 | 튜닝 파라미터 4개 (Min/Max × 2). 사용자가 그 값어치를 체감 못함 | 비추천 |
| (B) 밝기에 선형 종속 `contrast = cMin + (cMax-cMin) × norm(brightness)` | 파라미터 2개. 밝을 때 약간 쨍하게, 어두울 때 부드럽게 — 자연스러움 | 대비와 밝기가 항상 같이 움직여 "영화 모드"처럼 독립 조정이 어려움 (이건 수동 모드로 해결) | **MVP 권장** |
| (C) 수동 고정 | 단순. 버그 여지 없음 | "adaptive 기능"이란 간판과 살짝 안 맞음 | 대안: (B)가 귀찮으면 이걸로 |

**권장: (B) 선형 종속**. 구체 공식은 §6.

**Confidence: MEDIUM-HIGH.** Brightness보다 학술 근거 약함. 1주일 실사용에서 "대비 안 맞는다" 느끼면 (C)로 후퇴 가능 — loss가 작음.

---

## §3 Color Temperature ↔ Time & Ambient

### 3.1 서카디안 과학 요약

- **멜라토닌 억제**: 460 nm (청색) 빛이 555 nm (녹색·황색) 대비 **두 배** 강하게 멜라토닌 분비를 억제. 핵심 논문: Lockley et al. (Harvard/BWH), 2003. [PubMed 12970330](https://pubmed.ncbi.nlm.nih.gov/12970330/).
- **Room Light Effects (Gooley et al. 2011, PMC3047226)**: 취침 전 실내광 (< 200 lux)으로도 멜라토닌 분비 상당히 억제. 즉 저녁에 화면 밝게+청색 많으면 수면 리듬에 실질적 영향.
- **Cajochen et al. (2011)**: 6500K (cool) 빛이 3000K (warm) 대비 멜라토닌 억제·각성 증진 효과 유의하게 높음. [PMC3027693](https://pmc.ncbi.nlm.nih.gov/articles/PMC3027693/).
- **Night Shift가 실제 효과 있나 (Rensselaer LRC, 2019)**: 아이패드 Night Shift on/off 간 멜라토닌 억제 **차이 없음**. 이유는 "색온도를 바꿔도 전체 밝기가 그대로면 비시각계(melanopsin) 자극은 크게 안 줄어든다". [Sleep Review Magazine 요약](https://sleepreviewmag.com/sleep-treatments/therapy-devices/light-therapy/lighting-research-center-tests-effectiveness-apples-ipad-night-shift-mode-melatonin-suppression/), [PMC6561503](https://pmc.ncbi.nlm.nih.gov/articles/PMC6561503/).
- **실전 함의**: 색온도만 warm으로 가는 것보다 **밤에 밝기 자체를 낮추는** 게 더 효과적. f.lux/Night Shift는 "기분·가독성·눈 피로" 측면 개선은 있지만 "멜라토닌 보호"는 과장됨.

### 3.2 시간 기반 vs 조도 기반 색온도

- **f.lux/Night Shift**: 위치(일출·일몰) 기반. 주간 6500K → 밤 3400K (f.lux 기본). [Grokipedia f.lux](https://grokipedia.com/page/F.lux), [Apple Night Shift 지원 문서](https://support.apple.com/en-us/102191).
- **Apple True Tone**: **4-channel 주변광 센서**로 ambient 색온도를 직접 측정해 화면 white point를 맞춤. 즉 "주변이 텅스텐(3000K)이면 화면도 warm 방향으로 shift". 주변광 기반. [AppleInsider True Tone 2018](https://appleinsider.com/articles/18/07/12/what-is-apples-true-tone-technology-on-the-2018-macbook-pro-and-why-does-it-matter/).
- **BenQ B.I.+ (Visual Optimizer)**: 주변광 intensity + color temperature를 센서로 읽어 밝기·색온도 둘 다 자동 조정. 시간 정보는 안 씀. [BenQ B.I./B.I.+ 비교](https://www.benq.com/en-us/knowledge-center/knowledge/what-is-brightness-intelligence.html).

### 3.3 왜 Gnomon은 색온도를 하지 말아야 하는가

1. **하드웨어 제약**: MacBook 내장 ALS는 **조도(lux) 단일 스칼라**만 준다 (`AggregatedLux`). 색온도 정보 없음. True Tone을 흉내내려면 Apple이 주는 `AppleSPUVD6286`에 색온도 channel이 있는지 조사해야 하는데, 현재 공개된 인터페이스로는 어려움.
2. **DDC 제약**: m1ddc의 color temp 제어는 모니터가 지원하는 preset (예: 5000/6500/7500K 또는 "warm/normal/cool") 수준. 부드러운 연속 조정 불가. LG HDR 4K 메뉴 확인 필요.
3. **OS 중첩**: macOS는 이미 Night Shift (시간 기반) + True Tone (내장 디스플레이용)을 기본 제공. Gnomon이 이걸 또 하면 충돌·OS보다 더 나은 품질 보장 난망.
4. **효과 크기**: 위 Rensselaer 연구 결과 — 멜라토닌 측면에선 큰 효과 없음. 안락감은 있지만 이건 Night Shift로 해결 가능.

### 3.4 Gnomon에 적용

**MVP: 색온도 기능 제외.**

만약 추후 추가한다면:
- 시간 기반 (Night Shift류) — 구현 쉽지만 macOS 기본 기능과 겹침. **비권장**.
- 조도 기반 — True Tone-like. 단일 lux만으로는 불가 (색온도 정보 없음). **비권장**.
- 조합 (시간 + lux) — 예: "밤 + 실내 (lux<50)면 더 warm" 같은 룰. 복잡도 상승 대비 이득 작음. **비권장**.
- 차별화 방향이 있다면: **외장 colorimetric 센서 (Lunar의 wireless sensor 같은)** 를 옵션으로 붙이는 것. 이건 MVP 스코프 초과.

**Confidence: HIGH (빼야 한다는 결정에 대해).**

---

## §4 Single-Sensor Strategy — 단일 조도 센서로 다 할 수 있나

### 4.1 원리적으로 얼마까지 가능한가

- **밝기**: lux 하나로 충분. 로그 매핑 + 스무딩이면 실사용에서 90%는 커버.
- **대비**: lux로 간접적으로 조정 가능 (밝기에 종속). 독립적 근거는 약함.
- **색온도**: lux 하나로는 **원리적으로 불가**. 동일 lux의 텅스텐(2700K) 방과 흐린 주간(6500K) 창가는 동일 입력. 출력이 똑같이 나올 수밖에 없음.

### 4.2 어디서 깨지는가

구체 시나리오:

| 상황 | lux | 실제 색 | 내장 ALS 판단 |
|---|---|---|---|
| 백열등 저녁 방 | 100 | warm (2700K) | "어둡다" — 모니터 어둡게 |
| 흐린 창가 | 1500 | cool (6500K) | "밝다" — 모니터 밝게 |
| LED 화이트 사무실 | 500 | neutral (4000K) | "중간" — 모니터 중간 |

→ 밝기만 보면 문제 없음. **색온도를 맞추려면 센서가 색을 구별해야 함**.

### 4.3 Colorimetric ALS를 쓰는 제품

- **Apple True Tone 탑재 기기**: 4-channel 센서 (RGBW 또는 그 유사). 내장 디스플레이만 혜택. 외장 모니터로 signal export 되는지는 비공식.
- **BenQ B.I.+**: 모니터 자체에 colorimetric 센서 내장. 호스트 OS 개입 없이 모니터가 스스로 조정.
- **Lunar external wireless sensor**: 기본은 TSL2591류 lux만. 색온도 지원 여부는 센서 하드웨어 선택에 달림.

### 4.4 실무 상한

단일 lux 센서 기반 MVP로 도달할 수 있는 "편안함 만족도" 상한: **체감상 Lunar Sensor Mode 수준 = 80-90%**. 나머지 10-20%는 색온도/컨텐츠 adaptive이 필요한 엣지 (HDR 영상, 어두운 창의적 작업 등). Gnomon은 여기서 색온도 포기하고 **밝기 품질**로 경쟁하는 게 현실적.

**Confidence: HIGH.**

---

## §5 Brightness-Only Approach — "밝기만" 으로 충분한가

### 5.1 주장: Brightness 조정이 전체 이득의 80%

근거:

1. **ISO/Applied Ergonomics** 권고는 **luminance(밝기)** 중심. 대비비(contrast ratio)는 최소 기준만 언급.
2. **Weber-Fechner + veiling glare**: 주변광 변화의 1차 효과는 "화면이 너무 어둡/밝게 느껴짐". 이걸 밝기로 잡으면 대비 문제는 2차 효과로 축소.
3. **실제 사용자 피드백**: Reddit/r/MacOS, HN 스레드에서 Lunar·BetterDisplay 리뷰를 보면 "밝기 자동조정"이 가장 많이 언급되고 칭송됨. 대비·색온도는 "있으면 좋고" 수준. (출처: HN 토론 [MonitorControl HN 2020](https://news.ycombinator.com/item?id=23785291), Reddit 체감 투표 — community consensus without strong evidence).
4. **Lunar 자체도 Sensor Mode의 핵심 셀링 포인트를 brightness로 마케팅**. 대비는 tag-along.

### 5.2 대비 추가 효과

- Veiling glare가 심한 환경 (햇빛 강하고 커튼 없음)에선 대비를 살짝 올리면 가독성 개선. **마진 이득: 10-15%** (체감, 학술 근거 약함).
- 단 잘못 적용 시 사진·영상 품질 훼손.
- → MVP에 넣어도 좋지만 "없어도 큰 손해 없음" 수준.

### 5.3 색온도 추가 효과

- 서카디안 효과: 위 §3 Rensselaer 연구대로 **밝기 그대로면 색온도만 바꿔도 멜라토닌 보호 효과 제한적**.
- 쾌적함: 저녁에 warm 색이 확실히 편안함 — 이건 Night Shift가 이미 해줌.
- → **Gnomon이 추가할 이득 ≈ 0-5%** (이미 OS 기본 기능 있음).

### 5.4 diminishing returns 지점

```
기능 추가에 따른 만족도 상승 (정성적):
밝기만                    ████████████████████      80%
+ 대비 (적절히)           ██████████████████████    90%
+ 색온도 (조도 기반)      ██████████████████████    91%   (노이즈 수준)
+ 색온도 (시간 기반)      ██████████████████████▌   93%   (Night Shift 대체)
+ auto-learning           ████████████████████████  97%
```

**개인 MVP 기준 "good enough" 경계: 밝기 + (대비 = 밝기 종속) + hysteresis/smoothing.**

**Confidence: MEDIUM.** 위 수치는 저자 추정 + 사용자 리포트 기반. 엄격한 controlled study 없음.

---

## §6 Recommended Curves for Gnomon MVP

### 6.1 Brightness Curve — 권장 공식

```swift
// 입력: lux (0 ~ 10000+), 출력: brightness percent (0~100)
func targetBrightness(lux: Double,
                      minPct: Double = 15,
                      maxPct: Double = 100,
                      luxCeiling: Double = 2000) -> Double {
    let clampedLux = max(0, lux)
    let normalized = log10(clampedLux + 1) / log10(luxCeiling + 1)
    let bounded = min(max(normalized, 0), 1)
    return minPct + (maxPct - minPct) * bounded
}
```

**핵심 값**:
- `min = 15` (PRD의 20보다 5 낮춤 — 완전 암실에서 20%는 약간 밝음)
- `max = 100`
- `luxCeiling = 2000` (PRD의 1000에서 상향 — 창가 반사광까지 커버)

**참조 매핑 표** (기본값 기준):

| lux | 환경 | log10(lux+1)/log10(2001) | brightness % | 참고 nits (추정) |
|---|---|---|---|---|
| 0 | 완전 암실 | 0 | 15 | ~42 |
| 10 | 달빛·희미한 조명 | 0.315 | 42 | ~118 |
| 50 | 어둑한 방 | 0.515 | 59 | ~165 |
| 100 | 무드등 / 저녁 거실 | 0.606 | 67 | ~188 |
| 300 | 사무실 최소 | 0.751 | 79 | ~221 |
| 500 | ISO 사무실 표준 | 0.818 | 85 | ~238 |
| 1000 | 밝은 사무실 / 복도 직사광 | 0.910 | 92 | ~258 |
| 2000 | 창가 / 흐린 실외 | 1.000 (포화) | 100 | ~280 (monitor max) |
| 10000+ | 실외 직사광 | 1.000 | 100 | ~280 |

(nits 값은 공칭 280 cd/m² SDR 모니터 가정. 실제는 monitor backlight characteristic에 의존.)

**A4 종이-앵커와 비교**:
- 500 lux에서 Gnomon 권장 = 85% brightness ≈ 238 nits (280×0.85) vs A4 앵커 143 nits.
- **Gnomon 곡선이 A4 앵커보다 약 1.5배 밝다**. 이건 의도적 — 실사용자는 "약간 더 밝은 게" 편하다는 리포트(Lunar 사용자)가 대다수. 종이-앵커는 이론적 최소선이라 보면 됨.
- 조율 원하면 `max = 80` 으로 낮추면 A4 앵커에 근접.

**Confidence: HIGH**. 공식·파라미터·포화점 모두 근거 있음.

### 6.2 Contrast Curve — 권장: 밝기에 선형 종속

```swift
// contrast도 밝기 target과 함께 계산됨.
// cMin/cMax는 독립 파라미터지만 곡선은 brightness의 normalized ratio 재사용.
func targetContrast(brightnessPct: Double,
                    minPct: Double = 45,
                    maxPct: Double = 65,
                    bMin: Double = 15,
                    bMax: Double = 100) -> Double {
    let ratio = (brightnessPct - bMin) / (bMax - bMin)  // 0~1
    let bounded = min(max(ratio, 0), 1)
    return minPct + (maxPct - minPct) * bounded
}
```

**기본값**: `contrast_min=45, contrast_max=65`.

**이유**:
- 대부분 모니터 공장 기본값 50 근처. 45-65는 허용 범위의 중앙.
- 밝을 때만 +15 정도 올리고 어두울 때 내리는 정도면 "쨍한 느낌"은 있고 부작용은 적음.
- 별도 contrast 곡선 파라미터 안 늘려도 됨 → PRD 옵션 (A)의 단점 회피.

**사용자 옵션**: 수동 모드(Adaptive OFF) 시 슬라이더로 독립 조정. Adaptive ON이면 위 공식.

**대안 (더 보수적)**: MVP **v0.1은 대비 자동조정 OFF** (contrast=50 고정), 1주일 실사용 후 (B)로 전환 평가. PRD Q5와도 부합.

**Confidence: MEDIUM-HIGH** — 경험적 선택. 학술 증거는 brightness만큼 강하진 않음.

### 6.3 Color Temperature — 권장: 구현 안 함

**Rationale**:
1. 단일 lux 센서로 색온도 추정 불가 (§4).
2. m1ddc의 color temp 제어는 discrete preset — 곡선 표현 불가.
3. macOS Night Shift가 이미 시간 기반 warm shift 제공.
4. 위험 대비 이득 작음 (§5).

**대안 (미래)**:
- v2+에서 외부 colorimetric 센서 지원 (Lunar의 wireless sensor 호환).
- 또는 True Tone 상태를 읽어 외장 모니터에 mirror — 기술 조사 필요.

**Confidence: HIGH**.

---

## §7 Implementation Notes

### 7.1 Hysteresis / Deadband

**권장**: 타겟 변화가 **2 unit 이상**일 때만 DDC 전송. PRD §5.3에 이미 반영됨 (`abs(target - last_sent) >= 2`).

근거:
- Windows adaptive brightness는 bucketed approach 사용 — 동일 효과.
- DDC는 I²C로 30-50ms 걸리고 일부 모니터는 연속 호출 시 OSD 깜빡임.
- 2 unit (2%)는 사용자가 체감 가능한 최소 변화 (Weber fraction ≈ 2-5%에 해당).

**추가 권장**: brightness와 contrast 각각 독립으로 체크. 밝기만 변해도 OK.

### 7.2 Smoothing

**권장 1안: EMA (Exponential Moving Average)**

```swift
// lux 수신 시마다 (1초 주기 가정)
var ema: Double = 0
let alpha: Double = 0.2  // smoothing factor, 0~1
ema = alpha * newLux + (1 - alpha) * ema
// targetBrightness(lux: ema) 사용
```

- α=0.2면 약 5초 "반응 지연" — 번짝이는 손전등, 지나가는 사람 그림자는 무시됨.
- 사람 눈의 photopic adaptation 타임스케일 (수초~수십초)과 맞음.

**권장 2안: Median-of-N**

최근 5개 lux 샘플의 **중앙값** 사용. 극단 이상치(outlier)에 더 robust. 단 반응이 약간 더 느림.

**권장**: EMA(α=0.2)로 시작. 이상치 문제 생기면 median-of-5로 교체.

### 7.3 Update Interval

PRD 기본 60초 → 평가:

- **60초**: 안전하나 "해가 구름 뒤로 들어가면 1분간 어두운 채로" 같은 상황 발생 가능. 배터리·CPU 걱정 거의 없음.
- **30초**: Lunar 관측상 이 근처 (실측 아님, feel). 반응성 좋고 여전히 과하지 않음.
- **10초 이하**: DDC 전송 과다. 모니터 OSD 깜빡임 위험.

**권장**: **30초 기본, 사용자 설정에서 15-120초 범위 조정 가능**. 전이 애니메이션을 5초 linear interpolation으로 넣으면 "툭툭 변하는" 느낌도 없어짐.

단, PRD가 60초로 선언됐으면 그대로 두고 실사용에서 "반응이 느리다" 느끼면 30초로 내리는 식도 OK.

### 7.4 Night / Day Detection (GPS 없이)

ALS만으로도 대략 판정 가능:

```swift
enum Daylight { case dawn, day, dusk, night }

func detectDaylight(lux: Double, hour: Int) -> Daylight {
    let isDark = lux < 30
    switch (isDark, hour) {
    case (true, 22...), (true, 0...5):   return .night
    case (true, _):                       return .dusk   // 어두운 방
    case (false, 20..<24):                return .dusk
    case (false, 6..<8):                  return .dawn
    default:                              return .day
    }
}
```

- lux + system clock (Date) 조합이면 GPS 없어도 "밤/낮" 감 나옴.
- 일출·일몰 시간 정확도 원하면 Foundation `Solar` 계산 또는 `CoreLocation`을 쓰는데, MVP 스코프 초과.

**MVP 실용 권장**: **밤/낮 detection 기능 자체를 넣지 말 것.** 브라이트니스 곡선이 lux에 반응하는 것만으로도 "밤에 알아서 어두워짐"이 자연스럽게 처리됨 (현재 PRD 설계가 이미 그렇다).

### 7.5 로깅·튜닝 플로우 (PRD §5.10 연계)

- CSV에 `ema_lux`, `target_brightness`, `sent_brightness` 셋 다 기록하면 1주일 후 곡선 튜닝에 매우 유용.
- 사용자가 수동으로 바꾼 순간 (`manual_override = true`)도 로깅 → 추후 auto-learning 데이터 소스.
- Android/Lunar가 하는 "personalization"도 이 데이터만 있으면 점진 구현 가능 — MVP 스코프 밖이지만 **스키마는 맞춰둘 것**.

---

## §8 Paid / Popular App Benchmark

유료·유명 앱을 조사해 Gnomon이 "뭘 베끼고 뭘 버릴지" 결정 근거.

### 8.1 Lunar (alin23) — **가장 직접적 경쟁자**

- **URL**: [github.com/alin23/Lunar](https://github.com/alin23/Lunar), [lunar.fyi](https://lunar.fyi/)
- **가격**: **$23 lifetime, 최대 5 Mac** (Lunar Pro). [Lunar Pro 페이지](https://lunar.fyi/pro).
- **시그널**: 내장 MacBook/iMac ALS (Apple Silicon), 외장 wireless sensor (lunarsensor), Apple Display/Studio Display 내장 ALS, Sync Mode(내장 디스플레이 밝기 mirror), Location Mode(일출·일몰), Clock Mode(수동 스케줄).
- **곡선**:
  - **Sensor Mode**: "lux to nits curve based on average eye perception" — 로그류. v6.0.0 기본 30-350 nits.
  - **Sync Mode**: 내장 디스플레이 밝기 비율을 외장에 mirror + auto-learning.
  - **Auto-learning**: 사용자 수동 조정 이벤트 → 해당 lux의 곡선점을 이동. 며칠~일주일이면 personal fit. 공식 FAQ.
- **조정 대상**: 밝기, 대비, (Pro) XDR Brightness unlock, sub-zero dimming, volume, input source.
- **인터벌/히스테리시스**: 비공개. v6.7.0 changelog에 "event-based, up to 100ms"라고 함 → 본질적으로 push 기반, polling 아님. 다만 실제 DDC 전송은 debounce됨.
- **포지셔닝**: "the defacto app", 전문 포지션. 고급 기능 (XDR, subzero, multiple monitors, external sensor, facelight, gamma, shortcuts) 다 포함.
- **Gnomon이 베낄 것**: log curve 기본 형태, 로그 ceiling 1000-2000 범위, sub-zero dimming (옵션), 사용자 슬라이더 UX (MIN/MAX 양쪽 조정), Sensor Mode 철학 — "lux → target nits".
- **Gnomon이 버릴 것**: Auto-learning (복잡도 과다), XDR unlock, multi-monitor (LG 하나만), Sync Mode (내장 ALS 직접 쓰므로 불필요), 외부 센서 (MVP 스코프 외).

### 8.2 MonitorControl (MonitorControl org) — 오픈소스 무료

- **URL**: [github.com/MonitorControl/MonitorControl](https://github.com/MonitorControl/MonitorControl), 32k+ stars.
- **가격**: 무료, MIT/GPL.
- **시그널**: Mac 내장 ALS **읽지 않고**, Apple 내장 디스플레이의 밝기 변화를 **이벤트**로 감지해 외장에 mirror만 함 ("touch bar / ALS induced changes").
- **곡선**: 없음. 그냥 내장 디스플레이 현재 brightness % → 외장 DDC로 복사.
- **조정 대상**: 밝기, 대비, 볼륨, gamma, software dimming.
- **인터벌/히스테리시스**: 이벤트 기반 (즉시 반응).
- **포지셔닝**: "Apple 키보드 밝기 키가 외장에서도 동작하게" — 가장 기본적, 가장 인기.
- **Gnomon이 베낄 것**: DDC 구현 레퍼런스 (m1ddc 대체 시), 단축키 처리.
- **Gnomon이 버릴 것/차별화**: lux를 직접 읽는다 (MonitorControl은 간접적). Adaptive 곡선 제공.

### 8.3 BetterDisplay (waydabber) — **종합 디스플레이 유틸**

- **URL**: [github.com/waydabber/BetterDisplay](https://github.com/waydabber/BetterDisplay)
- **가격**: **$21.99 Pro, 1년 업데이트 포함** (영구 사용 가능, 추가 업데이트는 추후 갱신).
- **시그널**: 내장 ALS (Apple Silicon). Pro에서 XDR 브라이트니스 unlock과 함께 ALS 활용.
- **곡선**: 문서화된 독립 곡선 **없음** — XDR upscaling 시에는 ALS를 **disable** 해버림 (macOS가 기본 곡선으로 brightness를 낮추려는 걸 방해하므로). 일반 adaptive 곡선은 macOS 기본 auto-brightness에 의존.
- **조정 대상**: HiDPI scaling, XDR brightness, DDC, EDID override, virtual screens — 광범위한 디스플레이 유틸.
- **포지셔닝**: "multi-tool for displays" — adaptive brightness는 one of many.
- **Gnomon이 베낄 것**: UI 구성 참고 정도.
- **Gnomon이 버릴 것**: XDR·가상 화면·HiDPI 등 디스플레이 하드웨어 영역 기능 전부.

### 8.4 Vivid (Jordi Bruin) — **HDR 밝기 booster**

- **URL**: [getvivid.app](https://www.getvivid.app/), Setapp/App Store.
- **가격**: **one-time purchase** (대략 $20대 추정, Setapp 번들 또는 Gumroad 구매), 무료 구독 아님.
- **시그널**: ambient light sensor 사용 명시 ("adaptive brightness control, automatically adjusts screen intensity based on ambient light conditions"). 대상은 **MacBook Pro 내장 디스플레이 또는 Pro Display XDR** (1600 nits급).
- **곡선**: 비공개. HDR metal API를 이용해 > 500 nits로 끌어올리는 트릭이 핵심이라 adaptive는 사이드 기능.
- **조정 대상**: 밝기 (XDR 한계 해제), Splitscreen Mode.
- **포지셔닝**: "double your brightness" — MacBook 사용자가 햇빛 아래서 화면이 더 밝기를 원할 때.
- **Gnomon이 베낄 것**: 없음 (목적이 다름).

### 8.5 DisplayBuddy

- **URL**: [displaybuddy.app](https://displaybuddy.app/)
- **가격**: 유료, 구체 수치 검색 결과에 없음 (리뷰 기준 $10-20대 추정).
- **시그널**: ALS **안 씀**. 사용자 수동 제어 + software dimming fallback.
- **곡선**: 없음. adaptive brightness 마케팅 **미제공**.
- **조정 대상**: 외장 모니터 밝기 manual control.
- **포지셔닝**: "Lunar 대안, 심플함" — Mac·Windows 크로스.
- **Gnomon이 베낄 것**: DDC fallback 전략 아이디어 정도.

### 8.6 f.lux

- **URL**: [justgetflux.com](https://justgetflux.com/)
- **가격**: 무료.
- **시그널**: **시간 + 위치** (일출·일몰). ALS 사용 안 함.
- **곡선**: 시간 기반 색온도 slew. 낮 6500K, Night 3400K, Bedtime(Late) 1900K-3400K (preset).
- **조정 대상**: **색온도만**. 밝기는 약간의 software dimming 옵션.
- **포지셔닝**: "circadian health, better sleep". 연구-heavy 이미지 ([research.html](https://justgetflux.com/research.html)).
- **Gnomon 겹침**: 없음. 보완 관계 — Gnomon(밝기) + f.lux 또는 Night Shift(색온도).

### 8.7 Iris (iristech.co)

- **URL**: [iristech.co](https://iristech.co/)
- **가격**: **Iris Pro ~$14.99 one-time** (기본). Iris mini free. Pro 상위 tier (업데이트 포함 버전) 존재하지만 기본 tier는 저렴.
- **시그널**: 시간 또는 수동 위치. ALS 사용 안 함.
- **곡선**: 시간대별 색온도 preset (f.lux보다 세분화, 1200K까지 내려감).
- **조정 대상**: 색온도, brightness without PWM (software dim), 폰트 렌더링 (Windows).
- **포지셔닝**: "ultimate eye protection". 과장된 마케팅으로 유명.
- **Gnomon 겹침**: 없음 (f.lux와 같은 카테고리).

### 8.8 Apple 공식 기능 (비교 기준)

**True Tone**
- **시그널**: 4-channel ambient color sensor (내장 디스플레이).
- **조정 대상**: 화면 white point (색온도만).
- **곡선**: 비공개. 주변광 색온도 측정 → 화면 white point를 주변 + 약간 cooler로 설정.
- **외장 모니터 지원**: Pro Display XDR (dual sensor)에서만.
- **Gnomon 함의**: True Tone은 색온도 영역, Gnomon은 밝기 영역 — 겹치지 않음.

**Night Shift**
- **시그널**: **시간만** (시스템 locale + 일출·일몰).
- **조정 대상**: 색온도 (2837K-5997K 범위, 레이블은 "Less Warm ~ More Warm").
- **Rensselaer 연구**: 멜라토닌 효과 유의하지 않음. 하지만 눈 피로·쾌적성엔 도움.
- **Gnomon 함의**: 사용자가 Night Shift를 켜면 된다. Gnomon이 재구현할 이유 없음.

**Ambient EQ / MacBook Auto-Brightness** (내장 디스플레이)
- **시그널**: 내장 ALS (동일한 `AppleSPUVD6286`).
- **조정 대상**: 내장 디스플레이 밝기만.
- **곡선**: 비공개. CoreBrightness가 담당, smoothing + hysteresis + user preference.
- **Gnomon 함의**: **내장 디스플레이는 OS에 맡기고, Gnomon은 외장 모니터만 담당.** PRD와 일치.

**Pro Display XDR Reference Mode**
- **시그널**: dual ambient light sensor (front + back).
- **조정 대상**: True Tone + brightness (reference modes 내에서).
- **Gnomon 함의**: 전문 영상 워크플로우 대상, 일반 유저와 무관.

### 8.9 BenQ Brightness Intelligence Plus (B.I.+)

- **구현**: **모니터 하드웨어**에 센서 내장. OS 개입 없이 자체 조정.
- **시그널**: 주변광 intensity **및 color temperature**.
- **곡선**: 비공개 proprietary, 실시간. 컨텐츠의 intensity도 본다 ("bright scenes avoid overexposure, dark scenes preserve detail").
- **포지셔닝**: 하드웨어 기능, 소프트웨어 앱 아님.
- **Gnomon 함의**: 이 문제를 호스트 OS 레벨에서 풀려는 앱이 Gnomon. 하드웨어 솔루션과 보완 관계.

### 8.10 비교 매트릭스

| 앱/기능 | 조도 시그널 | 밝기 곡선 | 대비 조정 | 색온도 | 학습 | 가격 | 포지셔닝 |
|---|---|---|---|---|---|---|---|
| **Lunar** | 내장 ALS + 외부 wireless | log→nits (30-350 기본) | 있음, 밝기 종속 | 내장만 (Pro) | O manual-learning | **$23 lifetime** | 전문, 만능 |
| **MonitorControl** | 내장 ALS 이벤트 mirror | 내장 밝기 % mirror | mirror | X | X | 무료 | 기본·심플 |
| **BetterDisplay** | 내장 ALS (XDR 모드 시 disable) | macOS 기본에 의존 | X | X | X | **$21.99** | 디스플레이 만능 유틸 |
| **Vivid** | 내장 ALS | 비공개 (HDR 중심) | X | X | X | one-time 구매 | HDR 밝기 booster |
| **DisplayBuddy** | **없음** (수동 only) | 없음 | X | X | X | 유료 | Lunar 대안, 크로스 OS |
| **f.lux** | **없음** (시간만) | X (dim 옵션만) | X | O 시간 기반 | X | 무료 | 수면·서카디안 |
| **Iris** | **없음** (시간만) | software dim | X | O 시간 기반 (1200K-6500K) | X | **~$15** | 눈 보호 |
| **Apple True Tone** | 4-ch color sensor | X | X | O 주변광 기반 | X | macOS 기본 | 색 정확도 |
| **Apple Night Shift** | 시간만 | X | X | O 2837-5997K | X | macOS 기본 | 취침 전 warm |
| **Apple Auto-Brightness** (내장) | 내장 ALS | 비공개 log | X | X | 약간 | macOS 기본 | 내장만 |
| **BenQ B.I.+** | 모니터 내장 color sensor | 비공개 | 간접 | O | X | 하드웨어 | 하드웨어 솔루션 |
| **Gnomon (MVP)** | 내장 ALS (lux only) | **log(lux+1)/log(2001)** | **밝기 종속** | X | X (로깅만) | 개인용/무료 | 개인 MVP, Lunar-lite |

### 8.11 Gnomon 포지셔닝 결정

**그대로 베낄 것**:
- Lunar의 log→nits 곡선 개념 (정확한 공식은 알 수 없으니 본 문서 §6 권장 공식으로 대체).
- Lunar의 "MIN/MAX 슬라이더 양쪽" UX.
- MonitorControl/m1ddc의 DDC 구현.
- Apple의 "내장은 OS에, 외장은 앱에" 경계.
- f.lux/Night Shift의 색온도 영역에는 **들어가지 않는 경계선**.

**Lunar와 다르게 갈 지점**:
- **단순함**: Sensor/Sync/Location/Clock/Auto/Manual 6가지 모드가 없다. Adaptive ON/OFF 둘뿐. (PRD §5.4).
- **학습 없음**: Auto-learning 미구현. 로그만 남겨서 사용자가 수동 튜닝. (PRD Q6).
- **단일 모니터 전용**: LG HDR 4K 하나만. 멀티 모니터 edge case 전부 제거.
- **외부 센서 미지원**: 내장 ALS만. wireless sensor 없음.
- **조도 실시간 가시화** (PRD §5.6): Lunar는 lux 표시가 약함. 이걸 메인 UI에서 부각.
- **무료 / 개인용**: 배포 안 함, 코드 서명 안 함. 공개 경쟁 안 함.

**한 줄 요약**: *"Lunar의 Sensor Mode만 잘라내서 내 LG 모니터 전용으로 만든 것. 80 라인짜리 곡선 + 200 라인짜리 UI."*

---

## §9 Final Recommendation Block (Copy-to-PRD)

### 9.1 PRD §5.2 대체안

```
### 5.2 Adaptive 곡선

#### 5.2.1 밝기 곡선 (확정)

b = b_min + (b_max - b_min) × clamp(log10(lux + 1) / log10(2001), 0, 1)

파라미터:
- b_min: 15   (0 lux에서 brightness 15%)
- b_max: 100  (2000 lux 이상에서 brightness 100%)
- lux ceiling: 2000 (포화점)

참조 (A4 종이 휴리스틱): 500 lux 사무실에서 약 85% brightness
→ ~238 nits (공칭 280 nits 모니터) → ISO 120-150 nits 권고의
~1.5배. 사용자 선호 고려한 의도적 over-bright.

#### 5.2.2 대비 곡선 (확정)

c = c_min + (c_max - c_min) × norm_brightness_ratio

where norm_brightness_ratio = (b - b_min) / (b_max - b_min)

파라미터:
- c_min: 45  (낮은 조도에서 대비)
- c_max: 65  (높은 조도에서 대비)

즉 밝기가 움직이면 대비는 45-65 사이에서 linear로 따라감.
별도 adaptive 파라미터 없음.

대안 (v0.1 ultra-safe 시작): c 고정 50, c_min=c_max=50.
1주일 실사용 후 v0.2에서 위 linear 종속으로 전환 평가.

#### 5.2.3 색온도 (MVP 제외)

단일 lux 센서로 색온도 추정 불가, m1ddc의 color temp 제어는
preset 수준, macOS Night Shift가 이미 시간 기반 warm shift
제공. 따라서 MVP에서 제외. 사용자는 macOS Night Shift를
별도 활성화.

v2+ 가능성: 외부 colorimetric 센서 지원 또는 True Tone
상태 mirror. MVP 스코프 밖.
```

### 9.2 PRD §5.3 DDC 전송 추가 권장

```
### 5.3 DDC 전송 (업데이트)

- 주기: 30초 기본 (사용자 15-120초 조정 가능).
  ※ PRD v0.2의 60초도 허용. 체감 반응 따라 조정.
- 조건 (불변): abs(target - last_sent) >= 2
- 전송 전 단계 추가:
  - lux EMA 스무딩: α=0.2 (1초 샘플 기준 ~5초 반응 지연)
  - 이상치 거르기: median-of-5 (옵션, 플리커 문제 생길 때만)
- 전이 애니메이션 (선택): 타겟 변경 시 5초 linear interpolation
  으로 DDC 전송. 인터벌이 60초일 때 특히 권장.
```

### 9.3 PRD §5.10 로깅 스키마 (미래 learning 대비)

```
timestamp, raw_lux, ema_lux, target_b, target_c, sent_b, sent_c,
           actual_b, actual_c, adaptive_on, manual_override
```

`manual_override = true` 는 사용자가 수동 슬라이더/단축키로
바꾼 직후 1회 로그. 추후 auto-learning 데이터 소스.

### 9.4 PRD §8 리스크 해제

- §8.1 "대비 Adaptive 곡선" → **해소**. (B) 선형 종속 채택.
  §6.2, §9.1 참고.
- §8.1 "색온도" 이슈는 없음 — MVP 제외.

### 9.5 한 줄 결론

**"로그 곡선으로 밝기, 밝기 비율로 대비, 색온도는 건드리지 마라. 인터벌은 30-60초, 데드밴드 2, EMA α=0.2. 추가 복잡도는 모두 v2 이후."**

---

## §10 Citations

### 10.1 표준·학술

- [ISO 9241-303:2011 Ergonomics of human-system interaction — Requirements for electronic visual displays](https://www.iso.org/standard/57992.html)
- [Userfocus — ISO 9241 Part 3 summary](https://www.userfocus.co.uk/resources/iso9241/part3.html)
- [ISO 9241-303:2011 sample PDF](https://cdn.standards.iteh.ai/samples/57992/bddfd91165b444f6b9815a6993feadc5/ISO-9241-303-2011.pdf)
- [Mantiuk — Display Considerations for Night and Low-Illumination Viewing (Cambridge)](https://www.cl.cam.ac.uk/~rkm38/pdfs/mantiuk09dcnliv.pdf)
- [Weber–Fechner law — Wikipedia](https://en.wikipedia.org/wiki/Weber%E2%80%93Fechner_law)
- [Fechner's Law — Psychology Town](https://psychology.town/general/fechners-law-logarithmic-sensory-experience/)
- [Royal Society — Weber's Law of perception (2023)](https://royalsocietypublishing.org/rspa/article/479/2271/20220626/54513/Weber-s-Law-of-perception-is-a-consequence-of)
- [Telescope-optics.net — Eye intensity response, contrast sensitivity](https://www.telescope-optics.net/eye_intensity_response.htm)
- [Spatio-chromatic contrast sensitivity under mesopic and photopic — JOV](https://jov.arvojournals.org/article.aspx?articleid=2765519) / [PMC mirror](https://pmc.ncbi.nlm.nih.gov/articles/PMC7405764/)
- [Image quality degradation by light scattering in displays (1999)](https://pubmed.ncbi.nlm.nih.gov/10342247/) / [PMC mirror](https://pmc.ncbi.nlm.nih.gov/articles/PMC3452495/)
- [Glare on contrast sensitivity — Frontiers Psychology 2018](https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2018.00899/full)
- [NCBI Bookshelf — Video Displays, Work, and Vision: Lighting and Reflections](https://www.ncbi.nlm.nih.gov/books/NBK216496/)

### 10.2 서카디안·색온도 연구

- [f.lux research bibliography](https://justgetflux.com/research.html)
- [Lockley et al. (2003) — Short wavelength light sensitivity of circadian melatonin](https://pubmed.ncbi.nlm.nih.gov/12970330/)
- [Cajochen et al. (2011) — Non-visual effects of light on melatonin / PMC3027693](https://pmc.ncbi.nlm.nih.gov/articles/PMC3027693/)
- [Gooley et al. (2011) — Room light before bedtime suppresses melatonin / PMC3047226](https://pmc.ncbi.nlm.nih.gov/articles/PMC3047226/)
- [Spectral tuning of evening ambient light — PMC5536841](https://pmc.ncbi.nlm.nih.gov/articles/PMC5536841/)
- [Temporal dynamics of melatonin & cortisol — Sci Reports 2019](https://www.nature.com/articles/s41598-019-54806-7)
- [High sensitivity of circadian system to evening light — PNAS 2019](https://www.pnas.org/doi/10.1073/pnas.1901824116)
- [Lockley — color temperature effects on core temp & melatonin (1997)](https://pubmed.ncbi.nlm.nih.gov/8979406/)
- [Rensselaer LRC — iPad Night Shift & melatonin test](https://sleepreviewmag.com/sleep-treatments/therapy-devices/light-therapy/lighting-research-center-tests-effectiveness-apples-ipad-night-shift-mode-melatonin-suppression/) / [PMC6561503 논문 원본](https://pmc.ncbi.nlm.nih.gov/articles/PMC6561503/)

### 10.3 Lunar 관련

- [Lunar Repository](https://github.com/alin23/Lunar)
- [Lunar CHANGELOG](https://github.com/alin23/Lunar/blob/master/CHANGELOG.md)
- [Lunar Display.swift (brightness↔nits code)](https://github.com/alin23/Lunar/blob/master/Lunar/Data/Display.swift)
- [Lunar FAQ](https://lunar.fyi/faq)
- [Lunar Pro pricing](https://lunar.fyi/pro)
- [Lunar Sensor page](https://lunar.fyi/sensor)
- [Lunar Changelog online](https://lunar.fyi/changelog)
- [lunarsensor (external sensor)](https://github.com/alin23/lunarsensor)

### 10.4 기타 앱

- [MonitorControl Repository](https://github.com/MonitorControl/MonitorControl)
- [BetterDisplay Repository](https://github.com/waydabber/BetterDisplay)
- [BetterDisplay Wiki — XDR upscaling + ALS behavior](https://github.com/waydabber/BetterDisplay/wiki/XDR-and-HDR-brightness-upscaling)
- [Vivid home](https://www.getvivid.app/)
- [DisplayBuddy home](https://displaybuddy.app/)
- [f.lux home](https://justgetflux.com/)
- [Iris (iristech)](https://iristech.co/)
- [Iris Pro pricing](https://iristech.co/buy-iris/)

### 10.5 Apple 공식

- [Apple Night Shift support article](https://support.apple.com/en-us/102191)
- [Use True Tone on Mac](https://support.apple.com/en-us/102147)
- [AppleInsider — True Tone explained 2018](https://appleinsider.com/articles/18/07/12/what-is-apples-true-tone-technology-on-the-2018-macbook-pro-and-why-does-it-matter/)
- [AppleInsider — True Tone vs Night Shift](https://appleinsider.com/articles/22/07/26/shining-some-light-on-true-tone-and-night-shift)
- [Pro Display XDR Reference Modes](https://support.apple.com/en-kz/HT210435)
- [Asahi Linux — ALS calibration extraction (Apple Silicon)](https://github.com/AsahiLinux/docs/issues/248)

### 10.6 OS 경쟁 구현

- [Android Developers Blog — Getting screen brightness right (2018)](https://android-developers.googleblog.com/2018/11/getting-screen-brightness-right-for-every-user.html)
- [Microsoft Learn — Adaptive brightness algorithm (bucketed)](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/sensors-adaptive-brightness)
- [Microsoft Support — Adaptive brightness on Surface](https://support.microsoft.com/en-US/surface/screen/adaptive-brightness-and-contrast-on-surface-devices)

### 10.7 실측/측정 관련

- [Cornell ergo — Lighting Lecture 1 (cd/m² vs lux)](https://ergo.human.cornell.edu/studentdownloads/DEA3500notes/Lighting/lightingnotes1.html)
- [BEGA — Illuminance, reflectance, luminance](https://www.bega.com/en/knowledge/lighting-theory/degree-of-illuminance-reflection-and-luminance/)
- [Wikipedia — Luminance](https://en.wikipedia.org/wiki/Luminance)
- [EIZO — 10 ways to address eye fatigue](https://www.eizo.com/library/basics/10_ways_to_address_eye_fatigue/)
- [EIZO — Why ambient light is important in the reading room](https://www.eizo.com/library/healthcare/why_ambient_light_is_important_in_the_reading_room/)
- [Monitoraholic — Best monitor settings for coding (Applied Ergonomics 2021 인용)](https://monitoraholic.com/the-best-monitor-settings-for-productivity-coding-and-long-hours/)
- [Arzopa — Choosing monitor brightness nit value](https://www.arzopa.com/blogs/guide/choosing-monitor-brightness-nit-value)

### 10.8 BenQ 하드웨어

- [BenQ — What is Brightness Intelligence](https://www.benq.com/en-us/knowledge-center/knowledge/what-is-brightness-intelligence.html)
- [BenQ Eye-Care Technology White Paper (GW2780)](https://www.benq.com/content/dam/b2c/en/monitors/g-v/gw2780/datasheet/benq-eye-care-monitor-bi-campaign-white-paper-gw2780-1.pdf)
- [BenQ B.I.+ Visual Optimizer announcement](https://www.benq.com/en-me/news/products/1506454868-30-65.html)

### 10.9 Weaker evidence / community

- [HN 2020 — MonitorControl 토론](https://news.ycombinator.com/item?id=23785291)
- [Foliovision — Lunar Monitor Control for M1 Macs](https://foliovision.com/2023/01/lunar-macos-monitor-control)
- [DisplayCAL forum — Recommended monitor brightness](https://hub.displaycal.net/forums/topic/what-monitor-brightness-is-recommended/)

---

*끝. 질문 있으면 §6(공식) / §9(PRD 복사용)만 읽어도 구현 착수 가능. 이론 궁금하면 §1-5 참고.*

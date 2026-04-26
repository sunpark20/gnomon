# Software Dimming Algorithms — Century Iris 구현 참조

> 작성: 2026-04-26
> 목적: DDC→감마 전환 시 밝기/색온도/채도/명암 제어에 사용할 공식과 출처 정리

---

## 1. Kelvin → RGB 변환

### 1A. Tanner Helland 공식 (업계 표준, Public Domain)

출처: tannerhelland.com/2012/09/18/convert-temperature-rgb-algorithm-code.html
범위: 1000K ~ 40000K, 백색점 6500K

```
T = kelvin / 100

R: T ≤ 66 → 255
   T > 66 → 329.698727446 × (T - 60)^(-0.1332047592)

G: T ≤ 66 → 99.4708025861 × ln(T) - 161.1195681661
   T > 66 → 288.1221695283 × (T - 60)^(-0.0755148492)

B: T ≥ 66 → 255
   T ≤ 19 → 0
   else   → 138.5177312231 × ln(T - 10) - 305.0447927307

모든 값을 [0, 255]로 클램프 후 /255 → [0.0, 1.0] 비율
```

사용 프로젝트: LightBulb (MIT, 2.7K stars), blue-light-filter-mac-app, OpenDisplay

### 1B. Redshift Blackbody Table (물리학 기반, GPL v3)

출처: github.com/jonls/redshift (5.9K stars), src/colorramp.c
CIE 1964 10도 색일치 함수 기반, 242개 엔트리 (1000K~25100K, 100K 간격)

주요 값:
```
1000K:  (1.000, 0.182, 0.000)  — 깊은 주황-적
2700K:  (1.000, 0.782, 0.466)  — 백열등
3400K:  (1.000, 0.853, 0.665)  — 할로겐
6500K:  (1.000, 1.000, 1.000)  — D65 백색점
10000K: (0.789, 0.865, 1.000)  — 쿨 청백
```

### 1C. SCT 로그 근사 (Public Domain)

출처: github.com/faf0/sct, src/xsct.c
Redshift 테이블의 로그 함수 근사:

```
T < 6500K:
  R = 1.0
  G = clamp(-1.4775 + 0.2859 × ln(T - 700), 0, 1)
  B = clamp(-4.3832 + 0.6212 × ln(T - 700), 0, 1)

T ≥ 6500K:
  R = clamp(1.7539 - 0.1151 × ln(T - 5800), 0, 1)
  G = clamp(1.4922 - 0.0751 × ln(T - 5800), 0, 1)
  B = 1.0
```

### 선택 권장: Tanner Helland (public domain, 가장 널리 사용)

---

## 2. 통합 감마 테이블 생성

### Redshift 공식 (Gold Standard)

출처: jonls/redshift, src/colorramp.c

```
table[channel][i] = pow(
    (i / 255.0) × brightness × whitepoint[channel],
    1.0 / gamma[channel]
)
```

### Century Iris 통합 공식 (밝기 + 색온도 + 명암 + 채도)

```swift
func buildGammaTable(
    temperature: Int,      // 1000 - 10000 K
    brightness: Float,     // 0.08 - 1.0
    contrast: Float,       // 0.0 - 1.0
    saturation: Float      // 0.0 - 1.0
) -> ([Float], [Float], [Float]) {

    // 1. 색온도 → RGB 비율
    var (rMul, gMul, bMul) = kelvinToRGB(temperature)

    // 2. 채도 (채널을 휘도 가중 평균으로 당김, ITU-R BT.709)
    let avg = 0.2126 * rMul + 0.7152 * gMul + 0.0722 * bMul
    rMul = avg + saturation * (rMul - avg)
    gMul = avg + saturation * (gMul - avg)
    bMul = avg + saturation * (bMul - avg)

    // 3. 명암 (출력 범위 압축)
    let lo = 0.5 * (1.0 - contrast)
    let hi = 0.5 * (1.0 + contrast)

    // 4. 256 엔트리 테이블 생성
    var r = [Float](repeating: 0, count: 256)
    var g = [Float](repeating: 0, count: 256)
    var b = [Float](repeating: 0, count: 256)

    for i in 0..<256 {
        let v = lo + (hi - lo) * Float(i) / 255.0
        r[i] = clamp(v * brightness * rMul, 0, 1)
        g[i] = clamp(v * brightness * gMul, 0, 1)
        b[i] = clamp(v * brightness * bMul, 0, 1)
    }
    return (r, g, b)
}
```

---

## 3. Lux → 밝기 매핑

### 3A. Kim et al. (2018) — 실험 데이터

논문: "Optimum display luminance depends on white luminance" (Optical Engineering, 인용 30)

| 주변 조도 (lux) | 최적 밝기 하한 (cd/m²) | 최적 밝기 상한 (cd/m²) |
|---|---|---|
| 50 | 113 | 516 |
| 100 | 116 | 574 |
| 200 | 130 | 612 |
| 500 | 154 | 664 |
| 1000 | 177 | 737 |
| 2000 | 204 | 790 |
| 5000 | 246 | 836 |

### 3B. Lin et al. (2022) — 거멱 함수 모델

논문: "Optimum display luminance under a wide range" (Optics Express, 인용 17)

```
L_display = a × E_ambient^b
```

### 3C. Windows 11 ALR 테이블 (Microsoft 공식)

| Lux 범위 | 밝기 % |
|---|---|
| 0 ~ 10 | 10% |
| 5 ~ 50 | 25% |
| 15 ~ 100 | 40% |
| 60 ~ 300 | 55% |
| 150 ~ 400 | 70% |
| 250 ~ 650 | 85% |
| 350 ~ 2000 | 100% |

### 3D. Gnomon 기존 곡선 (베버-페히너 법칙)

```
target = b_min + (b_max - b_min) × clamp(log10(lux + 1) / log10(ceiling + 1), 0, 1)
```

기본값: minBrightness=0, maxBrightness=100, luxCeiling=2000, darkFloorLux=15

---

## 4. Lux → 색온도 (CCT) 매핑

### 4A. Choi & Suk (2014) — 핵심 공식 (R²=0.87, n=100)

논문: "User-preferred color temperature adjustment for smartphone display" (Optical Engineering, IEEE ICCE)

```
CCT_display = 6534.75 × log₁₀(CCT_ambient) - 16304.68
```

주의: 주변 CCT 센서가 필요. lux 센서만 있으면 시간/태양 고도로 CCT 추정 필요.

### 4B. 태양 고도 기반 CCT (서카디안 모델)

출처: Home Assistant Circadian Blueprint

```
CCT = 4791.67 - 3290.66 / (1 + 0.222 × elevation^0.81)
```

elevation = 태양 고도각 (0~90도), 범위: 2200K(수평) ~ 4000K(천정)

### 4C. Kruithof Curve 기반 실용적 매핑 (CCT 센서 없을 때)

| 주변 조도 (lux) | 권장 화면 CCT |
|---|---|
| < 50 | 2700K (야간) |
| 50 ~ 200 | 2700K ~ 3400K |
| 200 ~ 500 | 3400K ~ 5000K |
| ≥ 500 | 5000K ~ 6500K |

---

## 5. 멜라토닌/서카디안 보호

### 5A. CIE S 026 — MEDI (Melanopic Equivalent Daylight Illuminance)

```
MEDI = E_photopic × MDER
```

| CCT (K) | MDER | 멜라토닌 영향 (6500K 대비) |
|---|---|---|
| 2700 | 0.45 | 55% 감소 |
| 3000 | 0.56 | 44% 감소 |
| 4000 | 0.77 | 23% 감소 |
| 5000 | 0.97 | 3% 감소 |
| 6500 | 1.00 | 기준 |

기준: 낮 MEDI > 250, 밤 MEDI < 10

### 5B. Gimenez et al. (2022) — 멜라토닌 억제 예측 공식

논문: "Predicting melatonin suppression by light" (J. Pineal Research, 인용 76)

```
Suppression(%) = -100 / (1 + (log₁₀(MEDI × 10⁶) / (9.002 - 0.008×t - 0.462×pupil))^7.496) + 100
```

ED50: 208 lux MEDI (비확장 동공), 72 lux MEDI (확장 동공)

### 5C. West et al. (2011) — 블루 LED 용량-반응 (인용 490)

논문: "Blue light from LEDs elicits dose-dependent melatonin suppression" (J. Applied Physiology)

469nm 기준 ED50 = 14.19 μW/cm², R² = 0.99

---

## 6. 명암 (Contrast) 조정

### ISO 9241-303 기준

- 화면 대 주변 밝기 비: 1:3 ~ 1:6 권장
- 사무실 디스플레이: 100-150 cd/m² at 500 lux

### 감마 테이블로 명암 조정

```
// contrast: 0.0(평평) ~ 1.0(최대)
lo = 0.5 × (1.0 - contrast)   // 블랙포인트 올림
hi = 0.5 × (1.0 + contrast)   // 화이트포인트 내림
output[i] = lo + (hi - lo) × (i / 255.0)
```

---

## 7. 채도 (Saturation) 조정

학술적 lux→채도 공식은 존재하지 않음. 실무 관행:
- 어두운 환경 (< 50 lux): 10~20% 감소
- 밝은 환경: 변경 없음 (1.0)

감마 테이블 근사:
```
// ITU-R BT.709 휘도 가중치로 채널 평균화
avg = 0.2126 × R + 0.7152 × G + 0.0722 × B
R' = avg + saturation × (R - avg)
G' = avg + saturation × (G - avg)
B' = avg + saturation × (B - avg)
```

---

## 8. Century Iris 적용 파이프라인

```
MacBook 조도센서 (IORegistry)
    │
    ├─→ brightness = log_curve(lux)              // Gnomon 기존 곡선 재사용
    ├─→ CCT = kruithof_table(lux)                // CCT 센서 없으므로 lux 기반 매핑
    │       또는 solar_model(time, latitude)      // 시간 기반 서카디안 모드
    ├─→ saturation = lux < 50 ? 0.85 : 1.0       // 어두울 때만 감소
    ├─→ contrast = 1.0                            // 기본 유지 (추후 조정 가능)
    │
    └─→ buildGammaTable(brightness, CCT, saturation, contrast)
            │
            ├─→ kelvinToRGB(CCT) → (rMul, gMul, bMul)
            ├─→ 채도 적용 → 채널 평균으로 당김
            ├─→ 명암 적용 → 출력 범위 압축
            └─→ CGSetDisplayTransferByTable()
```

---

## 9. 참고 오픈소스

| 프로젝트 | Stars | 라이선스 | 참고 대상 |
|---|---|---|---|
| jonls/redshift | 5,900 | GPL v3 | 색온도 테이블, 태양 모델, 통합 공식 |
| faf0/sct | ~200 | Public domain | 로그 근사 공식 |
| Tyrrrz/LightBulb | 2,700 | MIT | Tanner Helland + 스케줄 (C#) |
| MonitorControl | 33,000 | MIT | 감마 테이블 + 오버레이 (Swift) |
| alin23/Lunar | 5,500 | MIT | 감마 zero-detection, crash recovery |
| sahilmishra0012/OpenDisplay | 14 | MIT | 미니멀 감마+오버레이 구현 |

---

## 10. 학술 논문 목록

### 밝기
- Kim et al. (2018) "Optimum display luminance depends on white luminance" — Optical Engineering (인용 30)
- Lin et al. (2022) "Optimum display luminance under a wide range" — Optics Express (인용 17)
- Huang et al. (2021) "Visual comfort of tablet devices under wide ambient light" — Applied Sciences (인용 14)

### 색온도
- Choi & Suk (2014) "User-preferred color temperature adjustment" — Optical Engineering / IEEE ICCE
- Xie et al. (2025) "Effects of screen color mode and color temperature on visual fatigue" — IJHCI (인용 14)
- Yu et al. (2016) "Color scheme adaptation leveraging ambient light" — IEEE TMC (인용 19)
- Han et al. (2021) "Desktop lighting for comfortable computer screen" — Work (인용 23)

### 멜라토닌/서카디안
- West et al. (2011) "Blue LED dose-dependent melatonin suppression" — J. Applied Physiology (인용 490)
- Gimenez et al. (2022) "Predicting melatonin suppression by light" — J. Pineal Research (인용 76)
- Schlangen & Price (2021) "Lighting environment and non-visual responses" — Frontiers in Neurology (인용 174)

### 표준
- ISO 9241-303: 디스플레이 인체공학
- CIE S 026: 멜라토닌 영향 측정 (MEDI)
- Microsoft Adaptive Brightness / Adaptive Color: 산업 참조 구현

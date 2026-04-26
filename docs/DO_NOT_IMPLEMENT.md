# 금지 목록 (Do-NOT-Implement)

> 이 목록의 항목은 절대 구현하지 않는다. 에이전트가 "있으면 좋겠다"고 판단해도 무시할 것.
> 변경이 필요하면 사용자와 논의 후 이 문서를 먼저 수정한다.

| # | 금지 항목 | 이유 |
|---|---|---|
| 1 | DDC/IOAVService 코드 | Private API, sandbox 차단, App Store 불가 |
| 2 | corebrightnessdiag subprocess 호출 | sandbox에서 외부 바이너리 실행 불가 |
| 3 | 채도(saturation) 조절 | 학술적 캘리브레이션 기준 없음 |
| 4 | 명암/대비(contrast) 소프트웨어 조절 | 모니터 OSD에서 사용자 직접 조절 |
| 5 | 캘리브레이션 (A4 용지 등) | 감마는 비율이라 모니터 무관, 불필요 |
| 6 | 멀티 모니터 동시 제어 | v2 예정 |
| 7 | Intel Mac 지원 | Apple Silicon only |
| 8 | 색온도(CCT) 수동 조절 | 항상 자동, 읽기 전용 표시만 |
| 9 | 오버레이 윈도우 fallback (NSWindow shade) | 감마만 사용, 별개 구현이라 scope 밖 |
| 10 | f.lux 충돌 감지/알림 | 사용자에게 맡김 |
| 11 | 내장 디스플레이 지원 | macOS Auto-Brightness + True Tone이 처리, 외장 모니터 전용 |
| 12 | 앱 아이콘 새 디자인 | 기존 Gnomon 아이콘 재사용 |
| 13 | 밝기 세기 조절 (약/중/강) | 모니터 OSD로 하드웨어 밝기 조절이 대안 |

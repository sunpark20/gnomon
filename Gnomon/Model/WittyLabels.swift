//
//  WittyLabels.swift
//  Gnomon
//
//  Per-category witty Korean captions (PRD §5.5.1).
//  Shuffled only when category *changes* to avoid flicker.
//

import Foundation

public enum WittyLabels {
    public static let phrases: [LuxCategory: [String]] = [
        .pitchDark: [
            "어둡네요... 영혼까지 어두워지지는 마세요.",
            "은은한 어둠이군요. 잠은 자고 계신가요?",
            "동굴에서 코딩 중이신가요?",
        ],
        .veryDim: [
            "분위기 있는 조명입니다. 와인 한 잔 어때요?",
            "잔잔한 무드네요. 졸음 조심하세요.",
            "촛불 켠 듯한 분위기입니다.",
        ],
        .dimIndoor: [
            "아늑한 작업실 같은 조명입니다.",
            "조명 하나만 더 켜셔도 좋을 것 같아요.",
            "독서하기 딱 좋은 빛이네요.",
        ],
        .office: [
            "전형적인 사무실 조명입니다.",
            "야근의 향기가 살짝 나는데요?",
            "표준적인 인간 활동 영역입니다.",
        ],
        .bright: [
            "밝고 활기찬 공간이네요!",
            "오늘 뭔가 좋은 일 있으세요?",
            "비타민 D가 슬슬 합성될 것 같습니다.",
        ],
        .softDaylight: [
            "햇살이 따뜻하게 들어오네요.",
            "광합성 시작합니다 🌱",
            "커튼을 살짝 닫아주셔도 좋을 듯.",
        ],
        .directSunlight: [
            "날씨가 너~~~무 좋네요. 나가서 팬티만 입고 가볍게 러닝 어때요?",
            "선글라스 챙기세요. 진심이에요.",
            "모니터가 한계에 다다랐습니다... 살려주세요.",
        ],
    ]

    /// Picks a fresh phrase for the given category. Uses the lux value as a
    /// deterministic-ish seed so the same category shows a stable phrase for
    /// its dwell time rather than flickering each sample.
    public static func pick(for category: LuxCategory, seed: Int = 0) -> String {
        let pool = phrases[category] ?? ["..."]
        guard !pool.isEmpty else { return "..." }
        let index = ((seed % pool.count) + pool.count) % pool.count
        return pool[index]
    }
}

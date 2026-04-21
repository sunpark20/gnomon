//
//  WittyLabels.swift
//  Gnomon
//
//  Per-category witty English captions (PRD §5.5.1).
//  Gamer humor + fantasy-novel wit.
//  Shuffled only when category *changes* to avoid flicker.
//

import Foundation

public enum WittyLabels {
    public static let phrases: [LuxCategory: [String]] = [
        .pitchDark: [
            "Darkness so deep, even the Rogue lost stealth.",
            "The bird that drinks tears would feel right at home.",
            "Cave-coding detected. Vitamin D critically low.",
            "Shadow Resonance triggered. Sleep to dispel.",
            "A blade drawn in this dark would cut nothing but doubt.",
            "The Lich King called. He wants his ambiance back.",
            "Not all who wander in darkness are lost — some just forgot the light switch.",
            "Those who fear the dark have never bled in daylight.",
            "Priest's Power Word: Fortitude fading. Light needed.",
            "Even shadows need something to cling to. Turn on a lamp.",
        ],
        .veryDim: [
            "Candlelight vibes. A glass of wine wouldn't hurt.",
            "The Goldshire Inn glows softer than this. Cozy.",
            "Firelight flickers. Good light for telling old stories.",
            "+1 Charisma buff active. Date-night lighting.",
            "A tear shed in dim light still finds its way down.",
            "Night-raid-ready illumination. Grab your gear.",
            "The innkeeper is working late. A quiet evening.",
            "Every wound looks kinder by candlelight.",
            "Arcane glow is unstable. Mana reserves low.",
            "The bird that drinks blood hunts best at dusk.",
        ],
        .dimIndoor: [
            "Cozy workshop lighting. Creative mode: ON.",
            "Perfect light for reading — or plotting a raid.",
            "Guild hall ambiance. Time to plan the next boss pull.",
            "The library hums with quiet magic. Researching?",
            "One who reads by dim light learns to see what others miss.",
            "NPC spawn imminent. Stay alert.",
            "Soul-bind comfort level. Nice.",
            "Elite-mob-hunting brightness. Bring potions.",
            "A prayer room's gentle glow. Peaceful.",
            "Council chamber lighting. Big decisions ahead.",
        ],
        .office: [
            "Standard office lighting. Daily quests await.",
            "A faint scent of overtime lingers in the air.",
            "Typical human activity zone detected.",
            "Quest-ready brightness. Time to farm some gold!",
            "Stormwind Square energy. Just another day of adventure.",
            "Eat, work, repeat — even heroes must hit max level.",
            "+5 Worker Stamina buff applied.",
            "The sword that cuts best is the one swung without hesitation.",
            "Even the farmers of Azeroth toil under this light.",
            "Orgrimmar war-room glow. Battle stations!",
        ],
        .bright: [
            "Bright and lively! Something good happening today?",
            "Vitamin D synthesis: initiating.",
            "Elwynn Forest on a sunny afternoon. Adventure calls!",
            "Mage's Arcane Intellect buff feels like this.",
            "+10 Energy recharged. PVP-ready!",
            "Those who have bled enough learn to love the light.",
            "The plains are sun-drenched. The Tauren rejoice.",
            "A hero's journey begins at this brightness level.",
            "Battle Shout active. All party members +5% Attack!",
            "Light this generous asks nothing in return — enjoy it.",
        ],
        .softDaylight: [
            "Warm sunlight streaming in. Lovely.",
            "Photosynthesis commencing. Be the plant you were meant to be.",
            "You might want to close the curtains a bit.",
            "Summer Festival in progress. Type /dance!",
            "Legendary-grade sunshine. Use immediately!",
            "Golden plains shimmer. Epic ring drop incoming!",
            "Light of the Naaru pouring in. (Not a Priest, though.)",
            "The bird that drinks tears flew toward the sun and never looked back.",
            "Harvest Festival glow. The fields are golden.",
            "Every scar shines silver in light this warm.",
        ],
        .directSunlight: [
            "Grab your sunglasses. Seriously.",
            "Your monitor is struggling... send help.",
            "Ragnaros-level radiance. Run for cover!",
            "Nuclear-grade brightness. Close the window. Now.",
            "+100% Solar Damage. Take cover immediately!",
            "Tanaris desert vibes. Dehydration debuff soon.",
            "A blade reflects the sun — the wise sheathe it, the fool stares.",
            "Your eyes are precious. Summoning a Frost Mage...",
            "The sun does not forgive, but it does not lie either.",
            "Even the bird that drinks blood would seek shade here.",
        ],
    ]

    /// Picks a phrase for the given category. Seed drives which of the 10
    /// phrases is shown; callers reseed on every sync so users see variety
    /// as the app runs.
    public static func pick(for category: LuxCategory, seed: Int = 0) -> String {
        let pool = phrases[category] ?? ["..."]
        guard !pool.isEmpty else { return "..." }
        let index = ((seed % pool.count) + pool.count) % pool.count
        return pool[index]
    }
}

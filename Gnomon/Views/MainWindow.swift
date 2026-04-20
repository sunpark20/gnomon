//
//  MainWindow.swift
//  Gnomon
//
//  Single-window main UI. Composes the four cards + status bar.
//  Subscribes to AutoLoopController and re-renders every 100ms via TimelineView.
//

import SwiftUI

struct MainWindow: View {
    @Bindable var controller: AutoLoopController
    @State private var lastCategory: LuxCategory = .office
    @State private var phraseSeed = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let category = LuxCategory.classify(controller.emaLux)
            let phrase = WittyLabels.pick(for: category, seed: phraseSeed)

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 20) {
                    AmbientSensorCard(
                        lux: controller.currentLux,
                        category: category,
                        wittyPhrase: phrase
                    )
                    .frame(width: 280)

                    VStack(spacing: 20) {
                        BrightnessCard(controller: controller)
                        ContrastCard(value: controller.contrast)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(20)

                StatusBar(
                    nextSyncSecondsRemaining: secondsUntilNextSync,
                    isPaused: controller.isPaused,
                    onPauseToggle: { controller.togglePause() },
                    onApplyNow: { controller.applyNow() }
                )
            }
            .background(Theme.background)
            .frame(minWidth: 820, minHeight: 500)
            .onChange(of: category) { _, newCategory in
                // Reseed the phrase only when the category changes, to avoid flicker.
                if newCategory != lastCategory {
                    lastCategory = newCategory
                    phraseSeed = Int.random(in: 0 ..< 1000)
                }
            }
        }
    }

    private var secondsUntilNextSync: Int {
        guard let nextSyncAt = controller.nextSyncAt else { return 0 }
        return max(0, Int(nextSyncAt.timeIntervalSinceNow))
    }
}

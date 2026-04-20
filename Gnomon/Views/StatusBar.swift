//
//  StatusBar.swift
//  Gnomon
//
//  Bottom bar: Pause / Apply Now buttons + Next sync countdown.
//  Phase 3 read-only. Phase 4 wires up actions.
//

import SwiftUI

struct StatusBar: View {
    let nextSyncSecondsRemaining: Int
    let isPaused: Bool
    let onPauseToggle: () -> Void
    let onApplyNow: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: 16) {
                Button(action: onPauseToggle) {
                    Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                        .labelStyle(.titleAndIcon)
                }
                Button(action: onApplyNow) {
                    Label("Apply Now", systemImage: "bolt.fill")
                        .labelStyle(.titleAndIcon)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .foregroundStyle(Theme.textSecondary)
                Text("Next sync in \(max(0, nextSyncSecondsRemaining))s")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(Theme.background.opacity(0.6))
    }
}

#Preview {
    StatusBar(
        nextSyncSecondsRemaining: 24,
        isPaused: false,
        onPauseToggle: {},
        onApplyNow: {}
    )
    .background(Theme.background)
}

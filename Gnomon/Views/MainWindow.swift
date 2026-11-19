//
//  MainWindow.swift
//  Gnomon
//
//  Single-window main UI. Composes the ambient / brightness / contrast cards.
//

import SwiftUI

struct MainWindow: View {
    let controller: AutoLoopController
    @Environment(\.openWindow) private var openWindow

    @State private var isWindowVisible = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            HStack(alignment: .top, spacing: 20) {
                SensorColumn(controller: controller, isWindowVisible: isWindowVisible)
                    .frame(width: 280)

                VStack(spacing: 20) {
                    BrightnessCard(
                        controller: controller,
                        isWindowVisible: isWindowVisible,
                        onSyncNow: { controller.applyNow() }
                    )
                    ContrastCard(controller: controller)
                }
                .frame(maxWidth: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(20)
            Spacer(minLength: 0)
        }
        .background(Theme.background)
        .frame(minWidth: 960)
        .background(WindowVisibilityReader(isVisible: $isWindowVisible))
        .environment(\.controlActiveState, .active)
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Button(action: { openWindow(id: "settings") }, label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.gold)
                    .contentShape(Rectangle())
            })
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }
}

private struct SensorColumn: View {
    let controller: AutoLoopController
    let isWindowVisible: Bool

    var body: some View {
        AmbientSensorCard(
            lux: isWindowVisible ? controller.currentLux : 0,
            monitorConnected: controller.monitorConnected
        ) {
            RotatingSensorMessage(controller: controller, isWindowVisible: isWindowVisible)
        }
    }
}

private struct RotatingSensorMessage: View {
    let controller: AutoLoopController
    let isWindowVisible: Bool
    @State private var epoch = Date.now
    @State private var message: DisplayMessage = .witty("")

    var body: some View {
        SensorMessageView(message: message)
            .task(id: isWindowVisible) {
                guard isWindowVisible else { return }
                while !Task.isCancelled {
                    let elapsed = max(0, Date.now.timeIntervalSince(epoch))
                    let turn = Int(elapsed / 10)
                    message = messageForTurn(turn)
                    do {
                        try await Task.sleep(for: .seconds(10 - elapsed.truncatingRemainder(dividingBy: 10)))
                    } catch {
                        return
                    }
                }
            }
    }

    private func messageForTurn(_ turn: Int) -> DisplayMessage {
        if !turn.isMultiple(of: 2) {
            let shouts = DeveloperShouts.visible()
            if !shouts.isEmpty { return .shout(shouts[(turn / 2) % shouts.count]) }
        }
        return .witty(WittyLabels.pick(for: .classify(controller.emaLux), seed: turn))
    }
}

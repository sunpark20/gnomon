//
//  MainWindow.swift
//  Gnomon
//
//  Single-window main UI. Composes the ambient / brightness / contrast cards.
//  Subscribes to AutoLoopController and re-renders every 100ms via TimelineView.
//

import SwiftUI

struct MainWindow: View {
    @Bindable var controller: AutoLoopController
    @Environment(\.openWindow) private var openWindow

    /// 메시지 한 턴 길이. sync 간격과는 독립 — sync는 DDC 쓰기 주기,
    /// 이건 UI 문구 교대 주기.
    private let turnDuration: TimeInterval = 10
    @State private var messageEpoch: Date = .now
    @State private var currentMessage: DisplayMessage = .witty("...")
    @State private var lastTurnIndex: Int = -1

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let category = LuxCategory.classify(controller.emaLux)
            let elapsed = max(0, context.date.timeIntervalSince(messageEpoch))
            let turnIndex = Int(elapsed / turnDuration)

            VStack(spacing: 0) {
                topBar
                HStack(alignment: .top, spacing: 20) {
                    AmbientSensorCard(
                        lux: controller.currentLux,
                        category: category,
                        message: currentMessage,
                        monitorConnected: controller.monitorConnected
                    )
                    .frame(width: 280)

                    VStack(spacing: 20) {
                        BrightnessCard(
                            controller: controller,
                            nextSyncSecondsRemaining: secondsUntilNextSync,
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
            .onChange(of: turnIndex) { _, newTurn in
                let cat = LuxCategory.classify(controller.emaLux)
                currentMessage = buildMessage(turnIndex: newTurn, category: cat)
                lastTurnIndex = newTurn
            }
            .onAppear {
                let cat = LuxCategory.classify(controller.emaLux)
                currentMessage = buildMessage(turnIndex: 0, category: cat)
                lastTurnIndex = 0
            }
        }
        .environment(\.controlActiveState, .active)
    }

    /// 짝수 턴 = 기본 위트 / 홀수 턴 = 개발자 외침.
    /// 외침 리스트가 비어 있으면 빈 화면이 뜨지 않도록 위트로 폴백.
    private func buildMessage(turnIndex: Int, category: LuxCategory) -> DisplayMessage {
        let isShoutTurn = !turnIndex.isMultiple(of: 2)
        if isShoutTurn {
            let shouts = DeveloperShouts.visible()
            if !shouts.isEmpty {
                let shoutIndex = (turnIndex / 2) % shouts.count
                return .shout(shouts[shoutIndex])
            }
        }
        return .witty(WittyLabels.pick(for: category, seed: turnIndex))
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

    private var secondsUntilNextSync: Int {
        guard let nextSyncAt = controller.nextSyncAt else { return 0 }
        return max(0, Int(nextSyncAt.timeIntervalSinceNow))
    }
}

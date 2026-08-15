//
//  UpdatesSection.swift
//  Gnomon
//
//  Settings section for the GitHub-release updater: launch-check toggle,
//  manual "Check Now" button, and last check status.
//

import SwiftUI

struct UpdatesSection: View {
    @ObservedObject private var checker = UpdateChecker.shared
    @AppStorage(UpdateChecker.disabledKey) private var updateCheckDisabled = false

    var body: some View {
        SettingsSection(title: "Updates", iconName: "arrow.down.circle") {
            Toggle("Check for updates at launch", isOn: checkAtLaunch)
                .font(.caption)
            Text("Updates are downloaded from the public GitHub releases of Gnomon.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                Button {
                    Task { await checker.checkManually() }
                } label: {
                    Label("Check Now", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(checker.isBusy)
                if checker.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            if let status = checker.statusMessage {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(Theme.gold)
            }
        }
    }

    private var checkAtLaunch: Binding<Bool> {
        Binding(
            get: { !updateCheckDisabled },
            set: { updateCheckDisabled = !$0 }
        )
    }
}

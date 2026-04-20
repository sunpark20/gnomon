//
//  OnboardingWindow.swift
//  Gnomon
//
//  Shown on first launch (PRD §5.9). Runs a 3-step checklist + a
//  color-temperature informational card.
//

import SwiftUI

struct OnboardingWindow: View {
    @Bindable var viewModel: OnboardingViewModel
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            header
            VStack(spacing: 12) {
                CheckRow(
                    title: "Detecting external monitor…",
                    state: viewModel.ddcState,
                    retry: { Task { await viewModel.runDDCCheck() } }
                )
                CheckRow(
                    title: "Checking ambient light sensor…",
                    state: viewModel.luxState,
                    retry: { Task { await viewModel.runLuxCheck() } }
                )
                CheckRow(
                    title: "Accessibility permission (for hotkeys)",
                    state: viewModel.accessibilityState,
                    retry: {
                        viewModel.requestAccessibilityPermission()
                        viewModel.runAccessibilityCheck()
                    }
                )
                ColorTempNotice()
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)

            Spacer()

            HStack(spacing: 16) {
                Button("Skip for now", action: onComplete)
                    .buttonStyle(.borderless)
                Spacer()
                Button(allReady ? "Start" : "Start Calibration", action: onComplete)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.gold)
                    .disabled(viewModel.ddcState == .running || viewModel.luxState == .running)
            }
            .padding(32)
        }
        .frame(width: 520, height: 540)
        .background(Theme.background)
        .task { await viewModel.runAll() }
    }

    private var allReady: Bool {
        viewModel.allPassed
    }

    private var header: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(Theme.gold)
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white)
                )
            Text("Welcome to Gnomon")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(Theme.textPrimary)
            Text("Let's get your environment perfectly calibrated.")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 40)
    }
}

private struct CheckRow: View {
    let title: String
    let state: OnboardingViewModel.CheckState
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if case .failed = state {
                Button("Retry", action: retry).buttonStyle(.borderless)
            }
        }
        .padding(12)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var statusIcon: some View {
        Group {
            switch state {
            case .pending:
                Image(systemName: "circle.dashed").foregroundStyle(Theme.textSecondary)
            case .running:
                ProgressView().controlSize(.small)
            case .passed:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.gold)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
        }
    }

    private var detailText: String {
        switch state {
        case .pending: "Not started"
        case .running: "Running…"
        case let .passed(detail): detail
        case let .failed(detail): detail
        }
    }
}

private struct ColorTempNotice: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle")
                .foregroundStyle(Theme.gold)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text("Color Temperature Notice")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                Text("Gnomon은 색온도를 조정하지 않습니다. macOS Night Shift 또는 f.lux를 함께 사용하세요.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

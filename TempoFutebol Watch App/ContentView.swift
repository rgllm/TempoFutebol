//
//  ContentView.swift
//  TempoFutebol Watch App
//
//  Created by Rogério Moreira on 29/04/2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var clock: MatchClockViewModel
    @StateObject private var heartRate: HeartRateObservable
    @State private var isResetConfirmationPresented = false

    private let buttonHaptics = WatchMatchHapticPlayer()

    init(clock: MatchClockViewModel? = nil, heartRate: HeartRateObservable? = nil) {
        _clock = StateObject(wrappedValue: clock ?? MatchClockViewModel())
        _heartRate = StateObject(wrappedValue: heartRate ?? HeartRateService())
    }

    var body: some View {
        NavigationStack {
            Group {
                if clock.shouldTick {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        let _ = clock.processTick(at: timeline.date)
                        mainContent(clock.displayState(at: timeline.date))
                    }
                } else {
                    mainContent(clock.displayState())
                }
            }
            .task {
                await heartRate.requestAuthorization()
                heartRate.startObserving()
            }
            .onDisappear {
                heartRate.stopObserving()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        handleTap { isResetConfirmationPresented = true }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Reset")
                }
            }
            .confirmationDialog(
                "Reset match?",
                isPresented: $isResetConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) {
                    handleTap { clock.resetMatch() }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func mainContent(_ display: MatchClockDisplayState) -> some View {
        VStack(spacing: 6) {
            header(display)

            VStack(spacing: 2) {
                if let caption = timeCaption(for: display) {
                    Text(caption)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Text(display.isAddedTime ? "+\(format(display.mainTime))" : format(display.mainTime))
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(display.isAddedTime ? .orange : .white)
                    .minimumScaleFactor(0.55)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)

            heartRatePill

            actionRow
        }
        .padding(.horizontal, 6)
        .scenePadding()
    }

    private var heartRatePill: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
                .imageScale(.medium)

            Text(heartRate.currentBPM.map { String($0) } ?? "--")
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)

            Text("BPM")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.regularMaterial, in: Capsule())
        .allowsHitTesting(false)
    }

    private func header(_ display: MatchClockDisplayState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(display.halfTitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if let statusLine = compactStatusLine {
                Text(statusLine)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactStatusLine: String? {
        switch clock.status {
        case .paused:
            return "Paused"
        case .halfFinished:
            return "Half-time"
        case .matchFinished:
            return "Full-time"
        case .ready, .running:
            return nil
        }
    }

    private func timeCaption(for display: MatchClockDisplayState) -> String? {
        switch clock.status {
        case .running:
            return display.isAddedTime ? "Extra" : nil
        case .ready:
            return "Left"
        case .paused:
            return display.isAddedTime ? "Extra" : "Left"
        case .halfFinished, .matchFinished:
            return nil
        }
    }

    private var actionRow: some View {
        let action = clock.primaryAction
        return HStack(spacing: 8) {
            Button {
                handleTap { clock.runPrimaryAction() }
            } label: {
                Label(action.title, systemImage: action.iconName)
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(tint(for: action.tintName))

            if clock.canWhistle {
                Button {
                    handleTap { clock.whistle() }
                } label: {
                    Label("Whistle", systemImage: "flag.checkered")
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.orange)
            }
        }
    }

    private func handleTap(_ action: () -> Void) {
        buttonHaptics.play(.buttonTap)
        action()
    }

    private func tint(for tintName: String) -> Color {
        switch tintName {
        case "yellow":
            return .yellow
        case "green":
            return .green
        default:
            return .green
        }
    }

    private func format(_ interval: TimeInterval) -> String {
        let totalSeconds = max(Int(interval.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct PreviewClockSnapshot: Codable {
    let half: MatchHalf
    let status: MatchClockStatus
    let startedAt: Date?
    let elapsedBeforeStart: TimeInterval
}

extension ContentView {
    @MainActor
    static func previewModel(
        elapsedIntoHalf: TimeInterval,
        half: MatchHalf = .first,
        status: MatchClockStatus = .running
    ) -> MatchClockViewModel {
        let suiteName = "TempoFutebol.preview.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            return MatchClockViewModel(haptics: PreviewNoOpHaptics(), reloadComplications: {})
        }
        userDefaults.removePersistentDomain(forName: suiteName)

        let t0 = Date(timeIntervalSince1970: 900_000)
        let snapshot = PreviewClockSnapshot(
            half: half,
            status: status,
            startedAt: t0,
            elapsedBeforeStart: 0
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            userDefaults.set(data, forKey: MatchClockStorage.persistenceKey)
        }

        return MatchClockViewModel(
            userDefaults: userDefaults,
            now: { t0.addingTimeInterval(elapsedIntoHalf) },
            haptics: PreviewNoOpHaptics(),
            reloadComplications: {}
        )
    }
}

private struct PreviewNoOpHaptics: MatchHapticPlaying {
    func play(_ event: MatchHapticEvent) {}
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView()
                .previewDisplayName("Ready")

            ContentView(clock: ContentView.previewModel(elapsedIntoHalf: 35 * 60))
                .previewDisplayName("35m elapsed")

            ContentView(clock: ContentView.previewModel(elapsedIntoHalf: 46 * 60))
                .previewDisplayName("Added time")

            #if DEBUG
            ContentView(heartRate: MockHeartRateService(fixedBPM: 132))
                .previewDisplayName("Heart rate")

            ContentView(heartRate: MockHeartRateService(fixedBPM: nil))
                .previewDisplayName("No heart rate")
            #endif
        }
    }
}

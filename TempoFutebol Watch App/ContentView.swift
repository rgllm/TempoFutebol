//
//  ContentView.swift
//  TempoFutebol Watch App
//
//  Created by Rogério Moreira on 29/04/2026.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.scenePhase) private var scenePhase
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
                        mainContent(clock.displayState(at: timeline.date), at: timeline.date)
                            .task(id: timeline.date) {
                                clock.processTick(at: timeline.date)
                            }
                    }
                } else {
                    mainContent(clock.displayState())
                }
            }
            .onAppear {
                clock.syncRuntimeSession()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                clock.syncRuntimeSession()
            }
            .task {
                await heartRate.requestAuthorization()
                heartRate.startObserving()
            }
            .onDisappear {
                heartRate.stopObserving()
            }
            .toolbar {
                if !isLuminanceReduced {
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

    @ViewBuilder
    private func mainContent(_ display: MatchClockDisplayState, at date: Date? = nil) -> some View {
        if isLuminanceReduced {
            alwaysOnContent(display)
        } else {
            activeContent(display, at: date)
        }
    }

    private func activeContent(_ display: MatchClockDisplayState, at date: Date?) -> some View {
        VStack(spacing: 6) {
            header(display, at: date)

            timeBlock(display, isDimmed: false)

            heartRatePill

            actionRow
        }
        .padding(.horizontal, 6)
        .scenePadding()
    }

    private func alwaysOnContent(_ display: MatchClockDisplayState) -> some View {
        VStack(spacing: 5) {
            Text(display.halfTitle)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(alwaysOnStatusLine(for: display))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            timeBlock(display, isDimmed: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 6)
        .scenePadding()
    }

    private func timeBlock(_ display: MatchClockDisplayState, isDimmed: Bool) -> some View {
        VStack(spacing: 2) {
            if !isDimmed, let caption = timeCaption(for: display) {
                Text(caption)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(display.isAddedTime ? "+\(format(display.mainTime))" : format(display.mainTime))
                .font(.system(size: isDimmed ? 48 : 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(timeColor(for: display, isDimmed: isDimmed))
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isDimmed ? 0 : 2)
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

    private func header(_ display: MatchClockDisplayState, at date: Date?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(display.halfTitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if let statusLine = activeStatusLine(at: date) {
                Text(statusLine)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(clock.isRuntimeLimitWarningVisible ? .yellow : .secondary)
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

    private func activeStatusLine(at date: Date?) -> String? {
        if clock.isRuntimeLimitWarningVisible {
            return "Awake ends soon"
        }

        return clock.runtimeDiagnosticsTitle(at: date) ?? compactStatusLine
    }

    private func alwaysOnStatusLine(for display: MatchClockDisplayState) -> String {
        if display.isAddedTime {
            return "Extra"
        }

        return display.statusTitle
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

    private func timeColor(for display: MatchClockDisplayState, isDimmed: Bool) -> Color {
        if display.isAddedTime {
            return isDimmed ? .orange.opacity(0.55) : .orange
        }

        return isDimmed ? .white.opacity(0.68) : .white
    }

    private var actionRow: some View {
        let action = clock.primaryAction
        let hasSecondaryAction = clock.canStartExtraTime || clock.canWhistle
        return HStack(spacing: 8) {
            Button {
                handleTap { clock.runPrimaryAction() }
            } label: {
                actionButtonLabel(title: action.title, iconName: action.iconName, isCompact: hasSecondaryAction)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(tint(for: action.tintName))

            if clock.canStartExtraTime {
                Button {
                    handleTap { clock.startExtraTime() }
                } label: {
                    actionButtonLabel(title: "Extra", iconName: "forward.end.fill", isCompact: true)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.orange)
                .accessibilityLabel("Start extra time")
            } else if clock.canWhistle {
                Button {
                    handleTap { clock.whistle() }
                } label: {
                    actionButtonLabel(title: "End", iconName: "flag.checkered", isCompact: true)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.orange)
                .accessibilityLabel("Whistle")
            }
        }
    }

    private func actionButtonLabel(title: String, iconName: String, isCompact: Bool) -> some View {
        HStack(spacing: isCompact ? 5 : 7) {
            Image(systemName: iconName)
                .font(.system(size: isCompact ? 15 : 18, weight: .bold))

            Text(title)
                .font(.system(size: isCompact ? 16 : 20, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
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
    let phase: MatchClockPhase
    let startedAt: Date?
    let elapsedBeforeStart: TimeInterval
}

extension ContentView {
    @MainActor
    static func previewModel(
        elapsedIntoHalf: TimeInterval,
        half: MatchHalf = .first,
        status: MatchClockStatus = .running,
        phase: MatchClockPhase = .regulation
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
            phase: phase,
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
            runtimeSession: PreviewNoOpRuntimeSession(),
            reloadComplications: {}
        )
    }
}

private struct PreviewNoOpHaptics: MatchHapticPlaying {
    func play(_ event: MatchHapticEvent) {}
}

private final class PreviewNoOpRuntimeSession: MatchRuntimeSessionControlling {
    let snapshot: MatchRuntimeSessionSnapshot = .inactive
    var onSnapshotChange: ((MatchRuntimeSessionSnapshot) -> Void)?

    func startKeepingAppActive() {}

    func stopKeepingAppActive() {}
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView()
                .previewDisplayName("Ready")

            ContentView(clock: ContentView.previewModel(elapsedIntoHalf: 35 * 60))
                .previewDisplayName("35m elapsed")

            ContentView(clock: ContentView.previewModel(elapsedIntoHalf: 46 * 60, phase: .extraTime))
                .previewDisplayName("Added time")

            ContentView(clock: ContentView.previewModel(elapsedIntoHalf: 35 * 60))
                .environment(\.isLuminanceReduced, true)
                .previewDisplayName("Always On")

            #if DEBUG
            ContentView(heartRate: MockHeartRateService(fixedBPM: 132))
                .previewDisplayName("Heart rate")

            ContentView(heartRate: MockHeartRateService(fixedBPM: nil))
                .previewDisplayName("No heart rate")
            #endif
        }
    }
}

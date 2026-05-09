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
    @State private var areControlsLocked = false
    @State private var isScoreEditorPresented = false
    @State private var isSummaryPresented = false
    @State private var isHapticSettingsPresented = false

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
                clock.recordHeartRate(heartRate.currentBPM)
            }
            .onChange(of: heartRate.currentBPM) { _, bpm in
                clock.recordHeartRate(bpm)
            }
            .onChange(of: clock.status) { _, status in
                guard status != .running else { return }
                areControlsLocked = false
            }
            .onDisappear {
                heartRate.stopObserving()
            }
            .toolbar {
                if !isLuminanceReduced, !areControlsLocked {
                    ToolbarItem(placement: .topBarLeading) {
                        if clock.status == .running {
                            Button {
                                handleTap { areControlsLocked = true }
                            } label: {
                                Image(systemName: "lock.fill")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Lock controls")
                        } else {
                            Button {
                                handleTap { isHapticSettingsPresented = true }
                            } label: {
                                Image(systemName: "bell.badge")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Haptic alerts")
                        }
                    }

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
            .sheet(isPresented: $isScoreEditorPresented) {
                scoreEditor
            }
            .sheet(isPresented: $isSummaryPresented) {
                summarySheet
            }
            .sheet(isPresented: $isHapticSettingsPresented) {
                hapticSettingsSheet
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
        GeometryReader { proxy in
            let metrics = MatchLayoutMetrics(containerHeight: proxy.size.height)

            VStack(spacing: metrics.verticalSpacing) {
                header(display, at: date, metrics: metrics)

                timeBlock(display, isDimmed: false, metrics: metrics)

                if areControlsLocked {
                    lockedControl(metrics)
                } else {
                    actionRow(metrics)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
            .scenePadding()
        }
    }

    private func alwaysOnContent(_ display: MatchClockDisplayState) -> some View {
        GeometryReader { proxy in
            let metrics = MatchLayoutMetrics(containerHeight: proxy.size.height)

            VStack(spacing: metrics.alwaysOnSpacing) {
                Text(display.halfTitle)
                    .font(.system(size: metrics.alwaysOnTitleSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(alwaysOnStatusLine(for: display))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                timeBlock(display, isDimmed: true, metrics: metrics)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, metrics.horizontalPadding)
            .scenePadding()
        }
    }

    private func timeBlock(
        _ display: MatchClockDisplayState,
        isDimmed: Bool,
        metrics: MatchLayoutMetrics
    ) -> some View {
        VStack(spacing: metrics.timeSpacing) {
            if !isDimmed, let caption = timeCaption(for: display) {
                Text(caption)
                    .font(.system(size: metrics.timeCaptionSize, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(display.isAddedTime ? "+\(format(display.mainTime))" : format(display.mainTime))
                .font(.system(size: isDimmed ? metrics.alwaysOnTimeSize : metrics.timeSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(timeColor(for: display, isDimmed: isDimmed))
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isDimmed ? 0 : metrics.timeVerticalPadding)
    }

    private func header(
        _ display: MatchClockDisplayState,
        at date: Date?,
        metrics: MatchLayoutMetrics
    ) -> some View {
        let statusLine = activeStatusLine(at: date)

        return HStack(alignment: metrics.headerAlignment, spacing: metrics.headerSpacing) {
            if metrics.usesCompactHeader {
                Text(shortHalfTitle)
                    .font(.system(size: metrics.headerTitleSize, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(width: metrics.compactHalfWidth, alignment: .leading)

                if let statusLine {
                    Text(statusLine)
                        .font(.system(size: metrics.compactStatusSize, weight: .semibold))
                        .foregroundStyle(clock.isRuntimeLimitWarningVisible ? .yellow : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Spacer(minLength: 0)
                }

                Group {
                    if areControlsLocked {
                        scoreLabel(metrics)
                    } else {
                        Button {
                            handleTap { isScoreEditorPresented = true }
                        } label: {
                            scoreLabel(metrics)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Score \(clock.score.home) to \(clock.score.away)")
                    }
                }
            } else {
                Group {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(display.halfTitle)
                            .font(.system(size: metrics.headerTitleSize, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        if let statusLine {
                            Text(statusLine)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(clock.isRuntimeLimitWarningVisible ? .yellow : .secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Group {
                    if areControlsLocked {
                        scoreLabel(metrics)
                    } else {
                        Button {
                            handleTap { isScoreEditorPresented = true }
                        } label: {
                            scoreLabel(metrics)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Score \(clock.score.home) to \(clock.score.away)")
                    }
                }
            }
        }
    }

    private func scoreLabel(_ metrics: MatchLayoutMetrics) -> some View {
        Text(metrics.usesCompactHeader ? clock.score.title : clock.score.compactTitle)
            .font(.system(size: metrics.scoreSize, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.vertical, metrics.scoreVerticalPadding)
            .padding(.horizontal, metrics.scoreHorizontalPadding)
            .background(.regularMaterial, in: Capsule())
    }

    private func lockedControl(_ metrics: MatchLayoutMetrics) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .imageScale(.medium)

            Text("Locked")
                .font(.system(size: metrics.actionFontSize, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: metrics.actionMinHeight)
        .foregroundStyle(.white)
        .background(.regularMaterial, in: Capsule())
        .contentShape(Capsule())
        .onLongPressGesture(minimumDuration: 0.8) {
            handleTap { areControlsLocked = false }
        }
        .accessibilityLabel("Controls locked")
        .accessibilityHint("Long press to unlock")
    }

    private var compactStatusLine: String? {
        switch clock.status {
        case .paused:
            return "Pause"
        case .halfFinished:
            return "HT"
        case .matchFinished:
            return "FT"
        case .ready, .running:
            return nil
        }
    }

    private var shortHalfTitle: String {
        switch clock.half {
        case .first:
            return "1H"
        case .second:
            return "2H"
        }
    }

    private func activeStatusLine(at date: Date?) -> String? {
        if clock.isRuntimeLimitWarningVisible {
            return "Awake ends soon"
        }

        if let breakStatus = clock.halfTimeBreakStatusTitle(at: date) {
            return breakStatus
        }

        return clock.runtimeDiagnosticsTitle(at: date) ?? compactStatusLine
    }

    private func alwaysOnStatusLine(for display: MatchClockDisplayState) -> String {
        if display.isBreakTimer {
            return display.isBreakFinished ? "Break done" : "Break"
        }

        if display.isAddedTime {
            return "Extra"
        }

        return compactStatusLine ?? display.statusTitle
    }

    private func timeCaption(for display: MatchClockDisplayState) -> String? {
        if display.isBreakTimer {
            return display.isBreakFinished ? "Break done" : "Break"
        }

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
        if display.isBreakTimer {
            return isDimmed ? .cyan.opacity(0.55) : .cyan
        }

        if display.isAddedTime {
            return isDimmed ? .orange.opacity(0.55) : .orange
        }

        return isDimmed ? .white.opacity(0.68) : .white
    }

    private func actionRow(_ metrics: MatchLayoutMetrics) -> some View {
        let action = clock.primaryAction
        let hasSummaryAction = clock.status == .matchFinished && clock.lastSummary != nil
        let hasSecondaryAction = clock.canStartExtraTime || clock.canWhistle || hasSummaryAction
        return HStack(spacing: metrics.actionSpacing) {
            Button {
                handleTap { clock.runPrimaryAction() }
            } label: {
                actionButtonLabel(
                    title: action.title,
                    iconName: action.iconName,
                    isCompact: hasSecondaryAction,
                    metrics: metrics
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(metrics.controlSize)
            .tint(tint(for: action.tintName))

            if clock.canStartExtraTime {
                Button {
                    handleTap { clock.startExtraTime() }
                } label: {
                    actionButtonLabel(
                        title: "Extra",
                        iconName: "forward.end.fill",
                        isCompact: true,
                        metrics: metrics
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(metrics.controlSize)
                .tint(.orange)
                .accessibilityLabel("Start extra time")
            } else if clock.canWhistle {
                Button {
                    handleTap { clock.whistle() }
                } label: {
                    actionButtonLabel(
                        title: "End",
                        iconName: "flag.checkered",
                        isCompact: true,
                        metrics: metrics
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(metrics.controlSize)
                .tint(.orange)
                .accessibilityLabel("Whistle")
            } else if hasSummaryAction {
                Button {
                    handleTap { isSummaryPresented = true }
                } label: {
                    actionButtonLabel(
                        title: "Stats",
                        iconName: "chart.bar.fill",
                        isCompact: true,
                        metrics: metrics
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(metrics.controlSize)
                .tint(.blue)
                .accessibilityLabel("Match summary")
            }
        }
    }

    private func actionButtonLabel(
        title: String,
        iconName: String,
        isCompact: Bool,
        metrics: MatchLayoutMetrics
    ) -> some View {
        HStack(spacing: isCompact ? metrics.compactActionLabelSpacing : 7) {
            Image(systemName: iconName)
                .font(.system(size: isCompact ? metrics.compactActionIconSize : metrics.actionIconSize, weight: .bold))

            Text(title)
                .font(.system(size: isCompact ? metrics.compactActionFontSize : metrics.actionFontSize, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, minHeight: metrics.actionMinHeight)
        .padding(.horizontal, metrics.actionHorizontalPadding)
        .contentShape(Rectangle())
    }

    private var scoreEditor: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Text(clock.score.title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)

                HStack(spacing: 10) {
                    scoreControl(
                        title: "Home",
                        score: clock.score.home,
                        decrement: clock.decrementHomeScore,
                        increment: clock.incrementHomeScore
                    )

                    scoreControl(
                        title: "Away",
                        score: clock.score.away,
                        decrement: clock.decrementAwayScore,
                        increment: clock.incrementAwayScore
                    )
                }
            }
            .padding(.horizontal, 8)
            .navigationTitle("Score")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        handleTap { isScoreEditorPresented = false }
                    }
                }
            }
        }
    }

    private func scoreControl(
        title: String,
        score: Int,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button {
                handleTap(increment)
            } label: {
                Image(systemName: "plus")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .accessibilityLabel("Add \(title) goal")

            Text(String(score))
                .font(.title2.monospacedDigit().weight(.bold))
                .lineLimit(1)

            Button {
                handleTap(decrement)
            } label: {
                Image(systemName: "minus")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.bordered)
            .disabled(score == 0)
            .accessibilityLabel("Remove \(title) goal")
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var summarySheet: some View {
        NavigationStack {
            if let summary = clock.lastSummary {
                VStack(alignment: .leading, spacing: 8) {
                    Text(summary.score.title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)

                    summaryRow("Total", value: format(summary.totalMatchDuration))
                    summaryRow("1st half", value: format(summary.firstHalfDuration))
                    summaryRow("2nd half", value: format(summary.secondHalfDuration))
                    summaryRow("+1H", value: format(summary.firstHalfAddedTime))
                    summaryRow("+2H", value: format(summary.secondHalfAddedTime))

                    summaryRow("Avg BPM", value: summary.averageHeartRate.map(String.init) ?? "--")

                    if let maxHeartRate = summary.maxHeartRate {
                        summaryRow("Max BPM", value: String(maxHeartRate))
                    }
                }
                .padding(.horizontal, 8)
                .navigationTitle("Summary")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            handleTap { isSummaryPresented = false }
                        }
                    }
                }
            } else {
                Text("No match")
                    .font(.headline)
                    .navigationTitle("Summary")
            }
        }
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }

    private var hapticSettingsSheet: some View {
        NavigationStack {
            List {
                Section("Regulation") {
                    ForEach(MatchHapticSettings.allowedCheckpointMinutes, id: \.self) { minute in
                        Toggle("\(minute)m", isOn: checkpointBinding(for: minute))
                    }
                }

                Section("Added Time") {
                    Toggle("Every minute", isOn: Binding(
                        get: { clock.hapticSettings.extraTimeMinuteAlertsEnabled },
                        set: { clock.setExtraTimeMinuteAlertsEnabled($0) }
                    ))
                }
            }
            .navigationTitle("Haptics")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        handleTap { isHapticSettingsPresented = false }
                    }
                }
            }
        }
    }

    private func checkpointBinding(for minute: Int) -> Binding<Bool> {
        Binding(
            get: { clock.hapticSettings.isCheckpointMinuteEnabled(minute) },
            set: { clock.setCheckpointMinute(minute, isEnabled: $0) }
        )
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

private struct MatchLayoutMetrics {
    let containerHeight: CGFloat

    private var isCompactHeight: Bool {
        containerHeight < 190
    }

    private var isTightHeight: Bool {
        containerHeight < 170
    }

    var usesCompactHeader: Bool {
        isCompactHeight
    }

    var controlSize: ControlSize {
        isCompactHeight ? .regular : .large
    }

    var headerAlignment: VerticalAlignment {
        usesCompactHeader ? .center : .top
    }

    var headerSpacing: CGFloat {
        isCompactHeight ? 6 : 8
    }

    var headerTitleSize: CGFloat {
        isTightHeight ? 17 : (isCompactHeight ? 18 : 20)
    }

    var compactHalfWidth: CGFloat {
        isTightHeight ? 30 : 34
    }

    var compactStatusSize: CGFloat {
        isTightHeight ? 13 : 14
    }

    var verticalSpacing: CGFloat {
        isTightHeight ? 2 : (isCompactHeight ? 4 : 6)
    }

    var horizontalPadding: CGFloat {
        isCompactHeight ? 2 : 6
    }

    var verticalPadding: CGFloat {
        isTightHeight ? 0 : 2
    }

    var alwaysOnSpacing: CGFloat {
        isCompactHeight ? 3 : 5
    }

    var alwaysOnTitleSize: CGFloat {
        isCompactHeight ? 15 : 17
    }

    var alwaysOnTimeSize: CGFloat {
        isTightHeight ? 40 : (isCompactHeight ? 44 : 48)
    }

    var timeSpacing: CGFloat {
        isCompactHeight ? 0 : 2
    }

    var timeCaptionSize: CGFloat {
        isCompactHeight ? 14 : 16
    }

    var timeSize: CGFloat {
        isTightHeight ? 34 : (isCompactHeight ? 38 : 44)
    }

    var timeVerticalPadding: CGFloat {
        isCompactHeight ? 0 : 2
    }

    var scoreSize: CGFloat {
        isCompactHeight ? 13 : 14
    }

    var scoreVerticalPadding: CGFloat {
        isCompactHeight ? 3 : 5
    }

    var scoreHorizontalPadding: CGFloat {
        isCompactHeight ? 6 : 8
    }

    var actionSpacing: CGFloat {
        isCompactHeight ? 6 : 8
    }

    var actionMinHeight: CGFloat {
        isTightHeight ? 38 : (isCompactHeight ? 42 : 52)
    }

    var actionHorizontalPadding: CGFloat {
        isCompactHeight ? 2 : 6
    }

    var actionIconSize: CGFloat {
        isCompactHeight ? 16 : 18
    }

    var compactActionIconSize: CGFloat {
        isCompactHeight ? 14 : 15
    }

    var actionFontSize: CGFloat {
        isCompactHeight ? 17 : 20
    }

    var compactActionFontSize: CGFloat {
        isCompactHeight ? 14 : 16
    }

    var compactActionLabelSpacing: CGFloat {
        isCompactHeight ? 3 : 5
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

//
//  MatchClockViewModel.swift
//  TempoFutebol Watch App
//
//  Created by Codex on 29/04/2026.
//

import Combine
import Foundation
import WidgetKit

@MainActor
final class MatchClockViewModel: ObservableObject {
    static let halfDuration: TimeInterval = 45 * 60
    static let halfTimeBreakDuration: TimeInterval = 15 * 60
    static let runtimeWarningLeadTime: TimeInterval = 5 * 60
    private static let persistenceKey = MatchClockStorage.persistenceKey

    @Published private(set) var half: MatchHalf = .first
    @Published private(set) var status: MatchClockStatus = .ready
    @Published private(set) var phase: MatchClockPhase = .regulation
    @Published private(set) var score: MatchScore = .zero
    @Published private(set) var hapticSettings: MatchHapticSettings = .standard
    @Published private(set) var lastSummary: MatchSummary?
    @Published private(set) var runtimeSessionSnapshot: MatchRuntimeSessionSnapshot = .inactive
    @Published private(set) var isRuntimeLimitWarningVisible = false

    private var startedAt: Date?
    private var elapsedBeforeStart: TimeInterval = 0
    private var halfTimeBreakStartedAt: Date?
    private var firstHalfElapsedDuration: TimeInterval?
    private var heartRateTotal = 0
    private var heartRateSampleCount = 0
    private var maxHeartRate: Int?
    private var lastProcessedElapsedSecond: Int?
    private var hasPlayedRuntimeLimitWarning = false
    private var hasPlayedHalfTimeBreakFinished = false
    private let userDefaults: UserDefaults
    private let now: () -> Date
    private let haptics: MatchHapticPlaying
    private let runtimeSession: MatchRuntimeSessionControlling
    private let reloadComplications: () -> Void

    init(
        userDefaults: UserDefaults? = nil,
        now: @escaping () -> Date = Date.init,
        haptics: MatchHapticPlaying? = nil,
        runtimeSession: MatchRuntimeSessionControlling? = nil,
        reloadComplications: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.userDefaults = userDefaults ?? MatchClockStorage.userDefaults
        self.now = now
        self.haptics = haptics ?? WatchMatchHapticPlayer()
        self.runtimeSession = runtimeSession ?? WatchExtendedRuntimeSessionController()
        self.reloadComplications = reloadComplications
        runtimeSessionSnapshot = self.runtimeSession.snapshot
        self.runtimeSession.onSnapshotChange = { [weak self] snapshot in
            self?.handleRuntimeSessionSnapshot(snapshot)
        }
        restoreSnapshot()
    }

    var canWhistle: Bool {
        (status == .running || status == .paused) && elapsed() >= Self.halfDuration
    }

    var canStartExtraTime: Bool {
        (status == .running || status == .paused) && phase == .regulation
    }

    var shouldTick: Bool {
        status == .running || isHalfTimeBreakActive
    }

    var primaryAction: PrimaryActionPresentation {
        switch status {
        case .ready:
            return PrimaryActionPresentation(title: "Start", iconName: "play.fill", tintName: "green")
        case .running:
            return PrimaryActionPresentation(title: "Pause", iconName: "pause.fill", tintName: "yellow")
        case .paused:
            return PrimaryActionPresentation(title: "Resume", iconName: "play.fill", tintName: "green")
        case .halfFinished:
            return PrimaryActionPresentation(title: "2nd Half", iconName: "play.fill", tintName: "green")
        case .matchFinished:
            return PrimaryActionPresentation(title: "New", iconName: "plus", tintName: "green")
        }
    }

    func runtimeDiagnosticsTitle(at date: Date? = nil) -> String? {
        guard status == .running else { return nil }

        switch runtimeSessionSnapshot.status {
        case .active, .expiring:
            guard let expirationDate = runtimeSessionSnapshot.expirationDate else {
                return "Awake"
            }

            let secondsRemaining = max(expirationDate.timeIntervalSince(date ?? now()), 0)
            let minutesRemaining = max(Int(ceil(secondsRemaining / 60)), 0)
            return "Awake · \(minutesRemaining)m"
        case .starting:
            return "Awake starting"
        case .inactive:
            return "Awake off"
        }
    }

    func displayState(at date: Date? = nil) -> MatchClockDisplayState {
        let elapsed = elapsed(at: date)
        let isAddedTime = phase == .extraTime
        let remaining = max(Self.halfDuration - elapsed, 0)
        let addedTime = max(elapsed - Self.halfDuration, 0)
        let breakRemaining = halfTimeBreakRemaining(at: date)
        let isBreakTimer = status == .halfFinished

        return MatchClockDisplayState(
            halfTitle: half.title,
            statusTitle: status.title,
            isAddedTime: isBreakTimer ? false : isAddedTime,
            isBreakTimer: isBreakTimer,
            isBreakFinished: isBreakTimer && breakRemaining == 0,
            mainTime: isBreakTimer ? breakRemaining : (isAddedTime ? addedTime : remaining),
            mainLabel: isBreakTimer ? "Break" : (isAddedTime ? "Added time" : "Time left"),
            addedTime: addedTime
        )
    }

    func processTick(at date: Date) {
        guard status == .running else {
            processHalfTimeBreakTick(at: date)
            lastProcessedElapsedSecond = nil
            isRuntimeLimitWarningVisible = false
            return
        }

        let currentElapsedSecond = max(Int(elapsed(at: date).rounded(.down)), 0)
        let previousElapsedSecond = lastProcessedElapsedSecond ?? max(currentElapsedSecond - 1, 0)
        updateRuntimeLimitWarning(at: date)

        guard currentElapsedSecond != previousElapsedSecond else { return }

        playMilestoneHaptic(previousElapsedSecond: previousElapsedSecond, currentElapsedSecond: currentElapsedSecond)
        lastProcessedElapsedSecond = currentElapsedSecond
    }

    func halfTimeBreakStatusTitle(at date: Date? = nil) -> String? {
        guard status == .halfFinished else { return nil }

        let secondsRemaining = halfTimeBreakRemaining(at: date)
        guard secondsRemaining > 0 else { return "Break done" }

        let minutesRemaining = max(Int(ceil(secondsRemaining / 60)), 0)
        return "Break · \(minutesRemaining)m"
    }

    func incrementHomeScore() {
        score.home += 1
        syncLastSummaryScore()
        persistSnapshot()
    }

    func decrementHomeScore() {
        guard score.home > 0 else { return }

        score.home -= 1
        syncLastSummaryScore()
        persistSnapshot()
    }

    func incrementAwayScore() {
        score.away += 1
        syncLastSummaryScore()
        persistSnapshot()
    }

    func decrementAwayScore() {
        guard score.away > 0 else { return }

        score.away -= 1
        syncLastSummaryScore()
        persistSnapshot()
    }

    func setCheckpointMinute(_ minute: Int, isEnabled: Bool) {
        hapticSettings.setCheckpointMinute(minute, isEnabled: isEnabled)
        persistSnapshot(shouldReloadComplications: false)
    }

    func setExtraTimeMinuteAlertsEnabled(_ isEnabled: Bool) {
        hapticSettings.extraTimeMinuteAlertsEnabled = isEnabled
        persistSnapshot(shouldReloadComplications: false)
    }

    func recordHeartRate(_ bpm: Int?) {
        guard status == .running, let bpm, bpm > 0 else { return }

        heartRateTotal += bpm
        heartRateSampleCount += 1
        maxHeartRate = max(maxHeartRate ?? bpm, bpm)
        persistSnapshot(shouldReloadComplications: false)
    }

    func runPrimaryAction() {
        switch status {
        case .ready, .paused:
            start()
        case .running:
            pause()
        case .halfFinished:
            startNextHalf()
        case .matchFinished:
            resetMatch()
        }
    }

    func syncRuntimeSession() {
        guard status == .running else {
            runtimeSession.stopKeepingAppActive()
            return
        }

        runtimeSession.startKeepingAppActive()
    }

    func whistle() {
        guard canWhistle else { return }

        if phase == .regulation {
            phase = .extraTime
            haptics.play(.whistle)
            persistSnapshot()
            return
        }

        stopClock()
        runtimeSession.stopKeepingAppActive()

        if half == .first {
            firstHalfElapsedDuration = elapsedBeforeStart
            status = .halfFinished
            startHalfTimeBreak()
            haptics.play(.halfTime)
        } else {
            lastSummary = makeSummary(secondHalfElapsedDuration: elapsedBeforeStart)
            status = .matchFinished
            haptics.play(.whistle)
            haptics.play(.matchFinished)
        }
        persistSnapshot()
    }

    func startExtraTime() {
        guard canStartExtraTime else { return }

        let currentElapsed = max(elapsed(), Self.halfDuration)
        elapsedBeforeStart = currentElapsed
        startedAt = now()
        status = .running
        phase = .extraTime
        halfTimeBreakStartedAt = nil
        lastProcessedElapsedSecond = max(Int(currentElapsed.rounded(.down)), Int(Self.halfDuration))
        hasPlayedRuntimeLimitWarning = false
        isRuntimeLimitWarningVisible = false
        runtimeSession.startKeepingAppActive()
        haptics.play(.whistle)
        persistSnapshot()
    }

    func resetMatch() {
        half = .first
        status = .ready
        phase = .regulation
        startedAt = nil
        elapsedBeforeStart = 0
        halfTimeBreakStartedAt = nil
        firstHalfElapsedDuration = nil
        score = .zero
        heartRateTotal = 0
        heartRateSampleCount = 0
        maxHeartRate = nil
        lastProcessedElapsedSecond = nil
        hasPlayedRuntimeLimitWarning = false
        hasPlayedHalfTimeBreakFinished = false
        isRuntimeLimitWarningVisible = false
        runtimeSession.stopKeepingAppActive()
        persistSnapshot()
    }

    private func start() {
        status = .running
        startedAt = now()
        halfTimeBreakStartedAt = nil
        lastProcessedElapsedSecond = max(Int(elapsedBeforeStart.rounded(.down)), 0)
        hasPlayedRuntimeLimitWarning = false
        isRuntimeLimitWarningVisible = false
        runtimeSession.startKeepingAppActive()
        haptics.play(.start)
        persistSnapshot()
    }

    private func pause() {
        stopClock()
        runtimeSession.stopKeepingAppActive()
        isRuntimeLimitWarningVisible = false
        status = .paused
        persistSnapshot()
    }

    private func startNextHalf() {
        guard let nextHalf = half.next else {
            resetMatch()
            return
        }

        firstHalfElapsedDuration = firstHalfElapsedDuration ?? elapsedBeforeStart
        half = nextHalf
        status = .running
        phase = .regulation
        startedAt = now()
        elapsedBeforeStart = 0
        halfTimeBreakStartedAt = nil
        lastProcessedElapsedSecond = 0
        hasPlayedRuntimeLimitWarning = false
        hasPlayedHalfTimeBreakFinished = false
        isRuntimeLimitWarningVisible = false
        runtimeSession.startKeepingAppActive()
        haptics.play(.start)
        persistSnapshot()
    }

    private func stopClock() {
        elapsedBeforeStart = elapsed()
        startedAt = nil
    }

    private var isHalfTimeBreakActive: Bool {
        status == .halfFinished && halfTimeBreakStartedAt != nil && halfTimeBreakRemaining() > 0
    }

    private func elapsed(at date: Date? = nil) -> TimeInterval {
        guard let startedAt else {
            return elapsedBeforeStart
        }

        return elapsedBeforeStart + (date ?? now()).timeIntervalSince(startedAt)
    }

    private func startHalfTimeBreak() {
        halfTimeBreakStartedAt = now()
        hasPlayedHalfTimeBreakFinished = false
    }

    private func halfTimeBreakRemaining(at date: Date? = nil) -> TimeInterval {
        guard let halfTimeBreakStartedAt else { return 0 }

        let elapsedBreak = (date ?? now()).timeIntervalSince(halfTimeBreakStartedAt)
        return max(Self.halfTimeBreakDuration - elapsedBreak, 0)
    }

    private func processHalfTimeBreakTick(at date: Date) {
        guard status == .halfFinished, halfTimeBreakRemaining(at: date) == 0 else { return }
        guard !hasPlayedHalfTimeBreakFinished else { return }

        hasPlayedHalfTimeBreakFinished = true
        haptics.play(.halfTimeBreakFinished)
        persistSnapshot()
    }

    private func makeSummary(secondHalfElapsedDuration: TimeInterval) -> MatchSummary {
        let firstHalfDuration = firstHalfElapsedDuration ?? Self.halfDuration
        let firstHalfAddedTime = max(firstHalfDuration - Self.halfDuration, 0)
        let secondHalfAddedTime = max(secondHalfElapsedDuration - Self.halfDuration, 0)
        let averageHeartRate: Int?

        if heartRateSampleCount > 0 {
            averageHeartRate = Int((Double(heartRateTotal) / Double(heartRateSampleCount)).rounded())
        } else {
            averageHeartRate = nil
        }

        return MatchSummary(
            finishedAt: now(),
            score: score,
            firstHalfDuration: firstHalfDuration,
            secondHalfDuration: secondHalfElapsedDuration,
            firstHalfAddedTime: firstHalfAddedTime,
            secondHalfAddedTime: secondHalfAddedTime,
            totalMatchDuration: firstHalfDuration + secondHalfElapsedDuration,
            averageHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate
        )
    }

    private func syncLastSummaryScore() {
        guard status == .matchFinished, let summary = lastSummary else { return }

        lastSummary = MatchSummary(
            finishedAt: summary.finishedAt,
            score: score,
            firstHalfDuration: summary.firstHalfDuration,
            secondHalfDuration: summary.secondHalfDuration,
            firstHalfAddedTime: summary.firstHalfAddedTime,
            secondHalfAddedTime: summary.secondHalfAddedTime,
            totalMatchDuration: summary.totalMatchDuration,
            averageHeartRate: summary.averageHeartRate,
            maxHeartRate: summary.maxHeartRate
        )
    }

    private func handleRuntimeSessionSnapshot(_ snapshot: MatchRuntimeSessionSnapshot) {
        runtimeSessionSnapshot = snapshot

        if snapshot.status == .starting {
            hasPlayedRuntimeLimitWarning = false
            isRuntimeLimitWarningVisible = false
        }

        if snapshot.status == .inactive {
            isRuntimeLimitWarningVisible = false
        }
    }

    private func updateRuntimeLimitWarning(at date: Date) {
        guard let expirationDate = runtimeSessionSnapshot.expirationDate else {
            isRuntimeLimitWarningVisible = false
            return
        }

        let secondsRemaining = expirationDate.timeIntervalSince(date)
        guard secondsRemaining >= 0, secondsRemaining <= Self.runtimeWarningLeadTime else {
            isRuntimeLimitWarningVisible = false
            return
        }

        isRuntimeLimitWarningVisible = true
        guard !hasPlayedRuntimeLimitWarning else { return }

        hasPlayedRuntimeLimitWarning = true
        haptics.play(.runtimeLimitWarning)
    }

    func playMilestoneHaptic(previousElapsedSecond: Int, currentElapsedSecond: Int) {
        let checkpointSeconds = hapticSettings.checkpointSeconds
        if checkpointSeconds.contains(where: { previousElapsedSecond < $0 && currentElapsedSecond >= $0 }) {
            haptics.play(.timeCheckpoint)
        }

        if phase == .extraTime, hapticSettings.extraTimeMinuteAlertsEnabled {
            let previousExtraMinute = extraMinute(at: previousElapsedSecond)
            let currentExtraMinute = extraMinute(at: currentElapsedSecond)
            if currentExtraMinute > previousExtraMinute, currentExtraMinute > 0 {
                haptics.play(.extraTimeMinute)
            }
        }
    }

    func extraMinute(at elapsedSecond: Int) -> Int {
        guard elapsedSecond >= Int(Self.halfDuration) else { return 0 }
        return (elapsedSecond - Int(Self.halfDuration)) / 60
    }
}

private extension MatchClockViewModel {
    struct ClockSnapshot: Codable {
        let half: MatchHalf
        let status: MatchClockStatus
        let phase: MatchClockPhase?
        let startedAt: Date?
        let elapsedBeforeStart: TimeInterval
        let halfTimeBreakStartedAt: Date?
        let firstHalfElapsedDuration: TimeInterval?
        let score: MatchScore?
        let hapticSettings: MatchHapticSettings?
        let lastSummary: MatchSummary?
        let heartRateTotal: Int?
        let heartRateSampleCount: Int?
        let maxHeartRate: Int?
        let hasPlayedHalfTimeBreakFinished: Bool?
    }

    func persistSnapshot(shouldReloadComplications: Bool = true) {
        let snapshot = ClockSnapshot(
            half: half,
            status: status,
            phase: phase,
            startedAt: startedAt,
            elapsedBeforeStart: elapsedBeforeStart,
            halfTimeBreakStartedAt: halfTimeBreakStartedAt,
            firstHalfElapsedDuration: firstHalfElapsedDuration,
            score: score,
            hapticSettings: hapticSettings,
            lastSummary: lastSummary,
            heartRateTotal: heartRateTotal,
            heartRateSampleCount: heartRateSampleCount,
            maxHeartRate: maxHeartRate,
            hasPlayedHalfTimeBreakFinished: hasPlayedHalfTimeBreakFinished
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        userDefaults.set(data, forKey: Self.persistenceKey)
        if shouldReloadComplications {
            reloadComplications()
        }
    }

    func restoreSnapshot() {
        guard
            let data = userDefaults.data(forKey: Self.persistenceKey),
            let snapshot = try? JSONDecoder().decode(ClockSnapshot.self, from: data)
        else {
            return
        }

        half = snapshot.half
        status = snapshot.status
        startedAt = snapshot.startedAt
        elapsedBeforeStart = snapshot.elapsedBeforeStart
        halfTimeBreakStartedAt = snapshot.halfTimeBreakStartedAt
        firstHalfElapsedDuration = snapshot.firstHalfElapsedDuration
        score = snapshot.score ?? .zero
        hapticSettings = snapshot.hapticSettings ?? .standard
        lastSummary = snapshot.lastSummary
        heartRateTotal = snapshot.heartRateTotal ?? 0
        heartRateSampleCount = snapshot.heartRateSampleCount ?? 0
        maxHeartRate = snapshot.maxHeartRate
        hasPlayedHalfTimeBreakFinished = snapshot.hasPlayedHalfTimeBreakFinished ?? false
        phase = snapshot.phase ?? inferredPhase(for: snapshot.status, elapsed: elapsed())
    }

    func inferredPhase(for status: MatchClockStatus, elapsed: TimeInterval) -> MatchClockPhase {
        switch status {
        case .running, .paused:
            return elapsed >= Self.halfDuration ? .extraTime : .regulation
        case .halfFinished, .matchFinished:
            return elapsed >= Self.halfDuration ? .extraTime : .regulation
        case .ready:
            return .regulation
        }
    }
}

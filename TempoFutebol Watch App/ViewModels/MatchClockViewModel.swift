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
    static let runtimeWarningLeadTime: TimeInterval = 5 * 60
    private static let persistenceKey = MatchClockStorage.persistenceKey

    @Published private(set) var half: MatchHalf = .first
    @Published private(set) var status: MatchClockStatus = .ready
    @Published private(set) var phase: MatchClockPhase = .regulation
    @Published private(set) var runtimeSessionSnapshot: MatchRuntimeSessionSnapshot = .inactive
    @Published private(set) var isRuntimeLimitWarningVisible = false

    private var startedAt: Date?
    private var elapsedBeforeStart: TimeInterval = 0
    private var lastProcessedElapsedSecond: Int?
    private var hasPlayedRuntimeLimitWarning = false
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
        status == .running
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

        return MatchClockDisplayState(
            halfTitle: half.title,
            statusTitle: status.title,
            isAddedTime: isAddedTime,
            mainTime: isAddedTime ? addedTime : remaining,
            mainLabel: isAddedTime ? "Added time" : "Time left",
            addedTime: addedTime
        )
    }

    func processTick(at date: Date) {
        guard status == .running else {
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
            status = .halfFinished
            haptics.play(.halfTime)
        } else {
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
        lastProcessedElapsedSecond = nil
        hasPlayedRuntimeLimitWarning = false
        isRuntimeLimitWarningVisible = false
        runtimeSession.stopKeepingAppActive()
        persistSnapshot()
    }

    private func start() {
        status = .running
        startedAt = now()
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

        half = nextHalf
        status = .running
        phase = .regulation
        startedAt = now()
        elapsedBeforeStart = 0
        lastProcessedElapsedSecond = 0
        hasPlayedRuntimeLimitWarning = false
        isRuntimeLimitWarningVisible = false
        runtimeSession.startKeepingAppActive()
        haptics.play(.start)
        persistSnapshot()
    }

    private func stopClock() {
        elapsedBeforeStart = elapsed()
        startedAt = nil
    }

    private func elapsed(at date: Date? = nil) -> TimeInterval {
        guard let startedAt else {
            return elapsedBeforeStart
        }

        return elapsedBeforeStart + (date ?? now()).timeIntervalSince(startedAt)
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
        let checkpointSeconds = [600, 1200, 1800, 2400, 2700]
        if checkpointSeconds.contains(where: { previousElapsedSecond < $0 && currentElapsedSecond >= $0 }) {
            haptics.play(.timeCheckpoint)
        }

        if phase == .extraTime {
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
    }

    func persistSnapshot() {
        let snapshot = ClockSnapshot(
            half: half,
            status: status,
            phase: phase,
            startedAt: startedAt,
            elapsedBeforeStart: elapsedBeforeStart
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        userDefaults.set(data, forKey: Self.persistenceKey)
        reloadComplications()
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

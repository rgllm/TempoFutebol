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
    private static let persistenceKey = MatchClockStorage.persistenceKey

    @Published private(set) var half: MatchHalf = .first
    @Published private(set) var status: MatchClockStatus = .ready

    private var startedAt: Date?
    private var elapsedBeforeStart: TimeInterval = 0
    private var lastProcessedElapsedSecond: Int?
    private let userDefaults: UserDefaults
    private let now: () -> Date
    private let haptics: MatchHapticPlaying
    private let reloadComplications: () -> Void

    init(
        userDefaults: UserDefaults? = nil,
        now: @escaping () -> Date = Date.init,
        haptics: MatchHapticPlaying? = nil,
        reloadComplications: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.userDefaults = userDefaults ?? MatchClockStorage.userDefaults
        self.now = now
        self.haptics = haptics ?? WatchMatchHapticPlayer()
        self.reloadComplications = reloadComplications
        restoreSnapshot()
    }

    var canWhistle: Bool {
        (status == .running || status == .paused) && elapsed() >= Self.halfDuration
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

    func displayState(at date: Date? = nil) -> MatchClockDisplayState {
        let elapsed = elapsed(at: date)
        let isAddedTime = elapsed >= Self.halfDuration
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
            return
        }

        let currentElapsedSecond = max(Int(elapsed(at: date).rounded(.down)), 0)
        let previousElapsedSecond = lastProcessedElapsedSecond ?? max(currentElapsedSecond - 1, 0)

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

    func whistle() {
        guard canWhistle else { return }
        stopClock()

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

    func resetMatch() {
        half = .first
        status = .ready
        startedAt = nil
        elapsedBeforeStart = 0
        lastProcessedElapsedSecond = nil
        persistSnapshot()
    }

    private func start() {
        status = .running
        startedAt = now()
        lastProcessedElapsedSecond = max(Int(elapsedBeforeStart.rounded(.down)), 0)
        haptics.play(.start)
        persistSnapshot()
    }

    private func pause() {
        stopClock()
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
        startedAt = now()
        elapsedBeforeStart = 0
        lastProcessedElapsedSecond = 0
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

    func playMilestoneHaptic(previousElapsedSecond: Int, currentElapsedSecond: Int) {
        let checkpointSeconds = [600, 1200, 1800, 2400, 2700]
        if checkpointSeconds.contains(where: { previousElapsedSecond < $0 && currentElapsedSecond >= $0 }) {
            haptics.play(.timeCheckpoint)
        }

        let previousExtraMinute = extraMinute(at: previousElapsedSecond)
        let currentExtraMinute = extraMinute(at: currentElapsedSecond)
        if currentExtraMinute > previousExtraMinute, currentExtraMinute > 0 {
            haptics.play(.extraTimeMinute)
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
        let startedAt: Date?
        let elapsedBeforeStart: TimeInterval
    }

    func persistSnapshot() {
        let snapshot = ClockSnapshot(
            half: half,
            status: status,
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
    }
}

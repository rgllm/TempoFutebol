import XCTest
@testable import TempoFutebol_Watch_App

@MainActor
final class MatchClockViewModelTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!
    private var currentDate: Date!

    override func setUp() {
        super.setUp()
        suiteName = "TempoFutebolTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        currentDate = Date(timeIntervalSince1970: 0)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
        currentDate = nil
        super.tearDown()
    }

    func testPrimaryActionFlowReadyRunningPausedRunning() {
        let viewModel = makeViewModel()
        XCTAssertEqual(viewModel.status, .ready)

        viewModel.runPrimaryAction()
        XCTAssertEqual(viewModel.status, .running)

        viewModel.runPrimaryAction()
        XCTAssertEqual(viewModel.status, .paused)

        viewModel.runPrimaryAction()
        XCTAssertEqual(viewModel.status, .running)
    }

    func testRunningClockKeepsRuntimeSessionActive() {
        let runtimeSession = RecordingRuntimeSessionController()
        let viewModel = makeViewModel(runtimeSession: runtimeSession)

        viewModel.runPrimaryAction()

        XCTAssertEqual(runtimeSession.startedCount, 1)
        XCTAssertEqual(runtimeSession.stoppedCount, 0)
    }

    func testRuntimeSessionSnapshotTracksLifecycle() {
        let runtimeSession = RecordingRuntimeSessionController()
        let viewModel = makeViewModel(runtimeSession: runtimeSession)
        let expirationDate = currentDate.addingTimeInterval(60 * 60)

        XCTAssertEqual(viewModel.runtimeSessionSnapshot.status, .inactive)

        viewModel.runPrimaryAction()
        XCTAssertEqual(viewModel.runtimeSessionSnapshot.status, .starting)

        runtimeSession.publish(
            MatchRuntimeSessionSnapshot(
                status: .active,
                expirationDate: expirationDate,
                lastInvalidationReason: nil,
                lastErrorDescription: nil
            )
        )
        XCTAssertEqual(viewModel.runtimeSessionSnapshot.status, .active)
        XCTAssertEqual(viewModel.runtimeSessionSnapshot.expirationDate, expirationDate)
        XCTAssertEqual(viewModel.runtimeDiagnosticsTitle(), "Awake · 60m")

        runtimeSession.publish(
            MatchRuntimeSessionSnapshot(
                status: .expiring,
                expirationDate: expirationDate,
                lastInvalidationReason: nil,
                lastErrorDescription: nil
            )
        )
        XCTAssertEqual(viewModel.runtimeSessionSnapshot.status, .expiring)

        runtimeSession.publish(
            MatchRuntimeSessionSnapshot(
                status: .inactive,
                expirationDate: expirationDate,
                lastInvalidationReason: "expired",
                lastErrorDescription: "Session ended"
            )
        )
        XCTAssertEqual(viewModel.runtimeSessionSnapshot.status, .inactive)
        XCTAssertEqual(viewModel.runtimeSessionSnapshot.lastInvalidationReason, "expired")
        XCTAssertEqual(viewModel.runtimeSessionSnapshot.lastErrorDescription, "Session ended")
        XCTAssertEqual(viewModel.runtimeDiagnosticsTitle(), "Awake off")
    }

    func testPauseStopsRuntimeSession() {
        let runtimeSession = RecordingRuntimeSessionController()
        let viewModel = makeViewModel(runtimeSession: runtimeSession)

        viewModel.runPrimaryAction()
        viewModel.runPrimaryAction()

        XCTAssertEqual(runtimeSession.startedCount, 1)
        XCTAssertEqual(runtimeSession.stoppedCount, 1)
    }

    func testPauseStopsRuntimeSessionSnapshot() {
        let runtimeSession = RecordingRuntimeSessionController()
        let viewModel = makeViewModel(runtimeSession: runtimeSession)

        viewModel.runPrimaryAction()
        runtimeSession.publish(
            MatchRuntimeSessionSnapshot(
                status: .active,
                expirationDate: currentDate.addingTimeInterval(60 * 60),
                lastInvalidationReason: nil,
                lastErrorDescription: nil
            )
        )

        viewModel.runPrimaryAction()

        XCTAssertEqual(viewModel.status, .paused)
        XCTAssertEqual(viewModel.runtimeSessionSnapshot.status, .inactive)
    }

    func testResetStopsRuntimeSession() {
        let runtimeSession = RecordingRuntimeSessionController()
        let viewModel = makeViewModel(runtimeSession: runtimeSession)

        viewModel.runPrimaryAction()
        viewModel.resetMatch()

        XCTAssertEqual(runtimeSession.startedCount, 1)
        XCTAssertEqual(runtimeSession.stoppedCount, 1)
    }

    func testRestoredRunningClockCanSyncRuntimeSession() {
        var viewModel: MatchClockViewModel? = makeViewModel()
        viewModel?.runPrimaryAction()
        viewModel = nil

        let runtimeSession = RecordingRuntimeSessionController()
        let restored = makeViewModel(runtimeSession: runtimeSession)

        restored.syncRuntimeSession()

        XCTAssertEqual(restored.status, .running)
        XCTAssertEqual(runtimeSession.startedCount, 1)
    }

    func testRuntimeLimitWarningFiresOnceWithinFiveMinutesOfExpiration() {
        let haptics = RecordingHapticPlayer()
        let runtimeSession = RecordingRuntimeSessionController()
        let viewModel = makeViewModel(haptics: haptics, runtimeSession: runtimeSession)

        viewModel.runPrimaryAction()
        runtimeSession.publish(
            MatchRuntimeSessionSnapshot(
                status: .active,
                expirationDate: currentDate.addingTimeInterval(MatchClockViewModel.runtimeWarningLeadTime + 1),
                lastInvalidationReason: nil,
                lastErrorDescription: nil
            )
        )
        haptics.reset()

        currentDate = currentDate.addingTimeInterval(1)
        viewModel.processTick(at: currentDate)
        currentDate = currentDate.addingTimeInterval(1)
        viewModel.processTick(at: currentDate)

        XCTAssertEqual(haptics.events, [.runtimeLimitWarning])
        XCTAssertTrue(viewModel.isRuntimeLimitWarningVisible)
    }

    func testRuntimeLimitWarningDoesNotFireWithoutExpirationDate() {
        let haptics = RecordingHapticPlayer()
        let runtimeSession = RecordingRuntimeSessionController()
        let viewModel = makeViewModel(haptics: haptics, runtimeSession: runtimeSession)

        viewModel.runPrimaryAction()
        runtimeSession.publish(
            MatchRuntimeSessionSnapshot(
                status: .active,
                expirationDate: nil,
                lastInvalidationReason: nil,
                lastErrorDescription: nil
            )
        )
        haptics.reset()

        currentDate = currentDate.addingTimeInterval(1)
        viewModel.processTick(at: currentDate)

        XCTAssertTrue(haptics.events.isEmpty)
        XCTAssertFalse(viewModel.isRuntimeLimitWarningVisible)
    }

    func testRuntimeLimitWarningDoesNotFireWhenPausedOrReset() {
        let haptics = RecordingHapticPlayer()
        let runtimeSession = RecordingRuntimeSessionController()
        let viewModel = makeViewModel(haptics: haptics, runtimeSession: runtimeSession)

        viewModel.runPrimaryAction()
        runtimeSession.publish(
            MatchRuntimeSessionSnapshot(
                status: .active,
                expirationDate: currentDate.addingTimeInterval(MatchClockViewModel.runtimeWarningLeadTime),
                lastInvalidationReason: nil,
                lastErrorDescription: nil
            )
        )
        viewModel.runPrimaryAction()
        haptics.reset()

        currentDate = currentDate.addingTimeInterval(1)
        viewModel.processTick(at: currentDate)

        XCTAssertTrue(haptics.events.isEmpty)
        XCTAssertFalse(viewModel.isRuntimeLimitWarningVisible)

        viewModel.resetMatch()
        viewModel.processTick(at: currentDate)

        XCTAssertTrue(haptics.events.isEmpty)
        XCTAssertFalse(viewModel.isRuntimeLimitWarningVisible)
    }

    func testWhistleAdvancesThroughRegulationExtraTimeHalfTimeAndFullTime() {
        let viewModel = makeViewModel()

        viewModel.runPrimaryAction()
        advanceToAddedTime()
        XCTAssertFalse(viewModel.displayState().isAddedTime)
        XCTAssertEqual(viewModel.displayState().mainTime, 0)

        viewModel.whistle()
        XCTAssertEqual(viewModel.status, .running)
        XCTAssertEqual(viewModel.half, .first)
        XCTAssertEqual(viewModel.phase, .extraTime)
        XCTAssertTrue(viewModel.displayState().isAddedTime)

        viewModel.whistle()
        XCTAssertEqual(viewModel.status, .halfFinished)

        viewModel.runPrimaryAction()
        XCTAssertEqual(viewModel.half, .second)
        XCTAssertEqual(viewModel.status, .running)
        XCTAssertEqual(viewModel.phase, .regulation)

        advanceToAddedTime()
        viewModel.whistle()
        XCTAssertEqual(viewModel.status, .running)
        XCTAssertEqual(viewModel.half, .second)
        XCTAssertEqual(viewModel.phase, .extraTime)

        viewModel.whistle()
        XCTAssertEqual(viewModel.status, .matchFinished)
    }

    func testWhistleBeforeAddedTimeDoesNothing() {
        let viewModel = makeViewModel()

        viewModel.runPrimaryAction()
        viewModel.whistle()

        XCTAssertEqual(viewModel.status, .running)
        XCTAssertEqual(viewModel.half, .first)
        XCTAssertEqual(viewModel.phase, .regulation)
        XCTAssertFalse(viewModel.canWhistle)
    }

    func testWhistleIntoExtraTimePreservesPausedStatus() {
        let viewModel = makeViewModel()

        viewModel.runPrimaryAction()
        advanceToAddedTime()
        viewModel.runPrimaryAction()

        XCTAssertEqual(viewModel.status, .paused)
        viewModel.whistle()

        XCTAssertEqual(viewModel.status, .paused)
        XCTAssertEqual(viewModel.phase, .extraTime)
        XCTAssertTrue(viewModel.displayState().isAddedTime)
    }

    func testStartExtraTimeFromPausedRegulationStartsAddedTimeImmediatelyAtZero() {
        let haptics = RecordingHapticPlayer()
        let runtimeSession = RecordingRuntimeSessionController()
        let viewModel = makeViewModel(haptics: haptics, runtimeSession: runtimeSession)

        viewModel.runPrimaryAction()
        currentDate = currentDate.addingTimeInterval(6)
        viewModel.runPrimaryAction()
        haptics.reset()

        XCTAssertTrue(viewModel.canStartExtraTime)
        viewModel.startExtraTime()

        XCTAssertEqual(viewModel.status, .running)
        XCTAssertEqual(viewModel.phase, .extraTime)
        XCTAssertEqual(viewModel.displayState().mainTime, 0)
        XCTAssertEqual(viewModel.displayState().addedTime, 0)
        XCTAssertEqual(haptics.events, [.whistle])
        XCTAssertEqual(runtimeSession.startedCount, 2)
        XCTAssertFalse(viewModel.canStartExtraTime)
        XCTAssertTrue(viewModel.canWhistle)

        currentDate = currentDate.addingTimeInterval(10)

        XCTAssertEqual(viewModel.displayState().mainTime, 10)
        XCTAssertEqual(viewModel.displayState().addedTime, 10)
    }

    func testStartExtraTimeFromRunningRegulationKeepsClockRunning() {
        let viewModel = makeViewModel()

        viewModel.runPrimaryAction()
        currentDate = currentDate.addingTimeInterval(6)

        XCTAssertTrue(viewModel.canStartExtraTime)
        viewModel.startExtraTime()

        XCTAssertEqual(viewModel.status, .running)
        XCTAssertEqual(viewModel.phase, .extraTime)
        XCTAssertEqual(viewModel.displayState().mainTime, 0)

        currentDate = currentDate.addingTimeInterval(10)

        XCTAssertEqual(viewModel.displayState().mainTime, 10)
    }

    func testLateWhistleKeepsAccumulatedAddedTime() {
        let viewModel = makeViewModel()

        viewModel.runPrimaryAction()
        advanceToAddedTime(90)
        viewModel.whistle()

        XCTAssertEqual(viewModel.phase, .extraTime)
        XCTAssertEqual(viewModel.displayState().mainTime, 90)
        XCTAssertEqual(viewModel.displayState().addedTime, 90)
    }

    func testResetClearsTimingAndState() {
        let viewModel = makeViewModel()

        viewModel.runPrimaryAction()
        currentDate = currentDate.addingTimeInterval(50)
        viewModel.runPrimaryAction() // pause to store elapsed

        viewModel.resetMatch()

        XCTAssertEqual(viewModel.half, .first)
        XCTAssertEqual(viewModel.status, .ready)
        XCTAssertEqual(viewModel.phase, .regulation)
        XCTAssertEqual(viewModel.displayState().mainTime, MatchClockViewModel.halfDuration)
        XCTAssertEqual(viewModel.displayState().addedTime, 0)
    }

    func testExtraTimePhasePersistsAcrossInstances() {
        var viewModel: MatchClockViewModel? = makeViewModel()
        viewModel?.runPrimaryAction()
        advanceToAddedTime()
        viewModel?.whistle()
        XCTAssertEqual(viewModel?.status, .running)
        XCTAssertEqual(viewModel?.phase, .extraTime)
        viewModel = nil

        let restored = makeViewModel()
        XCTAssertEqual(restored.status, .running)
        XCTAssertEqual(restored.half, .first)
        XCTAssertEqual(restored.phase, .extraTime)
    }

    func testLegacySnapshotWithoutPhaseInfersExtraTimeWhenElapsedPastRegulation() {
        let snapshot = LegacyClockSnapshot(
            half: .first,
            status: .running,
            startedAt: Date(timeIntervalSince1970: 0),
            elapsedBeforeStart: 0
        )
        let data = try! JSONEncoder().encode(snapshot)
        userDefaults.set(data, forKey: MatchClockStorage.persistenceKey)
        currentDate = Date(timeIntervalSince1970: MatchClockViewModel.halfDuration + 60)

        let restored = makeViewModel()

        XCTAssertEqual(restored.status, .running)
        XCTAssertEqual(restored.phase, .extraTime)
        XCTAssertEqual(restored.displayState().mainTime, 60)
    }

    func testHapticFeedbackForStartHalfTimeAndWhistle() {
        let haptics = RecordingHapticPlayer()
        let viewModel = makeViewModel(haptics: haptics)

        viewModel.runPrimaryAction()
        XCTAssertEqual(haptics.events, [.start])

        advanceToAddedTime()
        viewModel.whistle()
        XCTAssertEqual(haptics.events, [.start, .whistle])

        viewModel.whistle()
        XCTAssertEqual(haptics.events, [.start, .whistle, .halfTime])

        viewModel.runPrimaryAction()
        XCTAssertEqual(haptics.events, [.start, .whistle, .halfTime, .start])

        advanceToAddedTime()
        viewModel.whistle()
        XCTAssertEqual(haptics.events, [.start, .whistle, .halfTime, .start, .whistle])

        viewModel.whistle()
        XCTAssertEqual(haptics.events, [.start, .whistle, .halfTime, .start, .whistle, .whistle, .matchFinished])
    }

    func testPlaysRegularTimeCheckpointHaptics() {
        let haptics = RecordingHapticPlayer()
        let viewModel = makeViewModel(haptics: haptics)
        let checkpoints: [TimeInterval] = [600, 1200, 1800, 2400, 2700]

        viewModel.runPrimaryAction()
        haptics.reset()

        for checkpoint in checkpoints {
            currentDate = Date(timeIntervalSince1970: checkpoint)
            viewModel.processTick(at: currentDate)
        }

        XCTAssertEqual(haptics.events, Array(repeating: .timeCheckpoint, count: checkpoints.count))
    }

    func testPlaysEveryExtraTimeMinuteHaptic() {
        let haptics = RecordingHapticPlayer()
        let viewModel = makeViewModel(haptics: haptics)

        viewModel.runPrimaryAction()
        haptics.reset()

        currentDate = Date(timeIntervalSince1970: MatchClockViewModel.halfDuration)
        viewModel.processTick(at: currentDate)
        viewModel.whistle()
        haptics.reset()

        currentDate = Date(timeIntervalSince1970: MatchClockViewModel.halfDuration + 60)
        viewModel.processTick(at: currentDate)
        currentDate = Date(timeIntervalSince1970: MatchClockViewModel.halfDuration + 120)
        viewModel.processTick(at: currentDate)
        currentDate = Date(timeIntervalSince1970: MatchClockViewModel.halfDuration + 180)
        viewModel.processTick(at: currentDate)

        XCTAssertEqual(haptics.events, [.extraTimeMinute, .extraTimeMinute, .extraTimeMinute])
    }

    func testHalfTimeBreakStartsAfterFirstHalfAndFiresHapticOnce() {
        let haptics = RecordingHapticPlayer()
        let viewModel = makeViewModel(haptics: haptics)

        viewModel.runPrimaryAction()
        advanceToAddedTime()
        viewModel.whistle()
        viewModel.whistle()
        haptics.reset()

        XCTAssertEqual(viewModel.status, .halfFinished)
        XCTAssertTrue(viewModel.shouldTick)
        XCTAssertTrue(viewModel.displayState().isBreakTimer)
        XCTAssertEqual(viewModel.displayState().mainTime, MatchClockViewModel.halfTimeBreakDuration)
        XCTAssertEqual(viewModel.halfTimeBreakStatusTitle(), "Break · 15m")

        currentDate = currentDate.addingTimeInterval(MatchClockViewModel.halfTimeBreakDuration)
        viewModel.processTick(at: currentDate)
        viewModel.processTick(at: currentDate)

        XCTAssertEqual(haptics.events, [.halfTimeBreakFinished])
        XCTAssertFalse(viewModel.shouldTick)
        XCTAssertTrue(viewModel.displayState().isBreakFinished)
        XCTAssertEqual(viewModel.displayState().mainTime, 0)
        XCTAssertEqual(viewModel.halfTimeBreakStatusTitle(), "Break done")
    }

    func testScorePersistsAndResetClearsCurrentScore() {
        var viewModel: MatchClockViewModel? = makeViewModel()

        viewModel?.incrementHomeScore()
        viewModel?.incrementHomeScore()
        viewModel?.incrementAwayScore()
        viewModel = nil

        let restored = makeViewModel()
        XCTAssertEqual(restored.score, MatchScore(home: 2, away: 1))

        restored.resetMatch()

        XCTAssertEqual(restored.score, .zero)
    }

    func testMatchSummaryCapturesScoreAddedTimeTotalAndHeartRate() {
        let viewModel = makeViewModel()

        viewModel.incrementHomeScore()
        viewModel.incrementHomeScore()
        viewModel.incrementAwayScore()
        viewModel.runPrimaryAction()
        viewModel.recordHeartRate(120)
        viewModel.recordHeartRate(130)

        advanceToAddedTime(70)
        viewModel.whistle()
        viewModel.whistle()
        viewModel.runPrimaryAction()

        currentDate = currentDate.addingTimeInterval(MatchClockViewModel.halfDuration + 125)
        viewModel.recordHeartRate(140)
        viewModel.whistle()
        viewModel.whistle()

        let summary = viewModel.lastSummary
        XCTAssertEqual(viewModel.status, .matchFinished)
        XCTAssertEqual(summary?.score, MatchScore(home: 2, away: 1))
        XCTAssertEqual(summary?.firstHalfAddedTime, 70)
        XCTAssertEqual(summary?.secondHalfAddedTime, 125)
        XCTAssertEqual(summary?.totalMatchDuration, (MatchClockViewModel.halfDuration * 2) + 195)
        XCTAssertEqual(summary?.averageHeartRate, 130)
        XCTAssertEqual(summary?.maxHeartRate, 140)
    }

    func testScoreCorrectionAfterFullTimeUpdatesSummaryScore() {
        let viewModel = makeViewModel()

        viewModel.runPrimaryAction()
        advanceToAddedTime()
        viewModel.whistle()
        viewModel.whistle()
        viewModel.runPrimaryAction()
        advanceToAddedTime()
        viewModel.whistle()
        viewModel.whistle()

        XCTAssertEqual(viewModel.lastSummary?.score, .zero)

        viewModel.incrementHomeScore()

        XCTAssertEqual(viewModel.score, MatchScore(home: 1, away: 0))
        XCTAssertEqual(viewModel.lastSummary?.score, MatchScore(home: 1, away: 0))
    }

    func testCustomRegularCheckpointHaptics() {
        let haptics = RecordingHapticPlayer()
        let viewModel = makeViewModel(haptics: haptics)

        viewModel.setCheckpointMinute(10, isEnabled: false)
        viewModel.runPrimaryAction()
        haptics.reset()

        currentDate = Date(timeIntervalSince1970: 10 * 60)
        viewModel.processTick(at: currentDate)
        currentDate = Date(timeIntervalSince1970: 20 * 60)
        viewModel.processTick(at: currentDate)

        XCTAssertEqual(haptics.events, [.timeCheckpoint])
    }

    func testCanDisableExtraTimeMinuteHaptics() {
        let haptics = RecordingHapticPlayer()
        let viewModel = makeViewModel(haptics: haptics)

        viewModel.setExtraTimeMinuteAlertsEnabled(false)
        viewModel.runPrimaryAction()
        currentDate = Date(timeIntervalSince1970: MatchClockViewModel.halfDuration)
        viewModel.processTick(at: currentDate)
        viewModel.whistle()
        haptics.reset()

        currentDate = Date(timeIntervalSince1970: MatchClockViewModel.halfDuration + 60)
        viewModel.processTick(at: currentDate)

        XCTAssertTrue(haptics.events.isEmpty)
    }

    private func makeViewModel(
        haptics: MatchHapticPlaying? = nil,
        runtimeSession: MatchRuntimeSessionControlling? = nil
    ) -> MatchClockViewModel {
        MatchClockViewModel(
            userDefaults: userDefaults,
            now: { self.currentDate },
            haptics: haptics ?? NoOpHapticPlayer(),
            runtimeSession: runtimeSession ?? NoOpRuntimeSessionController(),
            reloadComplications: {}
        )
    }

    private func advanceToAddedTime(_ extraSeconds: TimeInterval = 0) {
        currentDate = currentDate.addingTimeInterval(MatchClockViewModel.halfDuration + extraSeconds)
    }
}

private struct LegacyClockSnapshot: Codable {
    let half: MatchHalf
    let status: MatchClockStatus
    let startedAt: Date?
    let elapsedBeforeStart: TimeInterval
}

private struct NoOpHapticPlayer: MatchHapticPlaying {
    func play(_ event: MatchHapticEvent) {}
}

private final class NoOpRuntimeSessionController: MatchRuntimeSessionControlling {
    let snapshot: MatchRuntimeSessionSnapshot = .inactive
    var onSnapshotChange: ((MatchRuntimeSessionSnapshot) -> Void)?

    func startKeepingAppActive() {}

    func stopKeepingAppActive() {}
}

private final class RecordingRuntimeSessionController: MatchRuntimeSessionControlling {
    private(set) var snapshot: MatchRuntimeSessionSnapshot = .inactive
    var onSnapshotChange: ((MatchRuntimeSessionSnapshot) -> Void)?
    private(set) var startedCount = 0
    private(set) var stoppedCount = 0

    func startKeepingAppActive() {
        startedCount += 1
        publish(
            MatchRuntimeSessionSnapshot(
                status: .starting,
                expirationDate: nil,
                lastInvalidationReason: nil,
                lastErrorDescription: nil
            )
        )
    }

    func stopKeepingAppActive() {
        stoppedCount += 1
        publish(.inactive)
    }

    func publish(_ snapshot: MatchRuntimeSessionSnapshot) {
        self.snapshot = snapshot
        onSnapshotChange?(snapshot)
    }
}

private final class RecordingHapticPlayer: MatchHapticPlaying {
    private(set) var events: [MatchHapticEvent] = []

    func play(_ event: MatchHapticEvent) {
        events.append(event)
    }

    func reset() {
        events.removeAll()
    }
}

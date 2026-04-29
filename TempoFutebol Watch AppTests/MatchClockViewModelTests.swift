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

    func testWhistleTransitionsHalfAndMatchFinish() {
        let viewModel = makeViewModel()

        viewModel.runPrimaryAction()
        advanceToAddedTime()
        viewModel.whistle()
        XCTAssertEqual(viewModel.status, .halfFinished)
        XCTAssertEqual(viewModel.half, .first)

        viewModel.runPrimaryAction()
        XCTAssertEqual(viewModel.half, .second)
        XCTAssertEqual(viewModel.status, .running)

        advanceToAddedTime()
        viewModel.whistle()
        XCTAssertEqual(viewModel.status, .matchFinished)
    }

    func testWhistleBeforeAddedTimeDoesNothing() {
        let viewModel = makeViewModel()

        viewModel.runPrimaryAction()
        viewModel.whistle()

        XCTAssertEqual(viewModel.status, .running)
        XCTAssertEqual(viewModel.half, .first)
        XCTAssertFalse(viewModel.canWhistle)
    }

    func testResetClearsTimingAndState() {
        let viewModel = makeViewModel()

        viewModel.runPrimaryAction()
        currentDate = currentDate.addingTimeInterval(50)
        viewModel.runPrimaryAction() // pause to store elapsed

        viewModel.resetMatch()

        XCTAssertEqual(viewModel.half, .first)
        XCTAssertEqual(viewModel.status, .ready)
        XCTAssertEqual(viewModel.displayState().mainTime, MatchClockViewModel.halfDuration)
        XCTAssertEqual(viewModel.displayState().addedTime, 0)
    }

    func testStatePersistsAcrossInstances() {
        var viewModel: MatchClockViewModel? = makeViewModel()
        viewModel?.runPrimaryAction()
        advanceToAddedTime()
        viewModel?.whistle()
        XCTAssertEqual(viewModel?.status, .halfFinished)
        viewModel = nil

        let restored = makeViewModel()
        XCTAssertEqual(restored.status, .halfFinished)
        XCTAssertEqual(restored.half, .first)
    }

    func testHapticFeedbackForStartHalfTimeAndWhistle() {
        let haptics = RecordingHapticPlayer()
        let viewModel = makeViewModel(haptics: haptics)

        viewModel.runPrimaryAction()
        XCTAssertEqual(haptics.events, [.start])

        advanceToAddedTime()
        viewModel.whistle()
        XCTAssertEqual(haptics.events, [.start, .halfTime])

        viewModel.runPrimaryAction()
        XCTAssertEqual(haptics.events, [.start, .halfTime, .start])

        advanceToAddedTime()
        viewModel.whistle()
        XCTAssertEqual(haptics.events, [.start, .halfTime, .start, .whistle])
    }

    private func makeViewModel(haptics: MatchHapticPlaying? = nil) -> MatchClockViewModel {
        MatchClockViewModel(
            userDefaults: userDefaults,
            now: { self.currentDate },
            haptics: haptics ?? NoOpHapticPlayer(),
            reloadComplications: {}
        )
    }

    private func advanceToAddedTime() {
        currentDate = currentDate.addingTimeInterval(MatchClockViewModel.halfDuration)
    }
}

private struct NoOpHapticPlayer: MatchHapticPlaying {
    func play(_ event: MatchHapticEvent) {}
}

private final class RecordingHapticPlayer: MatchHapticPlaying {
    private(set) var events: [MatchHapticEvent] = []

    func play(_ event: MatchHapticEvent) {
        events.append(event)
    }
}

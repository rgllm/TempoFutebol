//
//  MatchClockState.swift
//  TempoFutebol Watch App
//
//  Created by Codex on 29/04/2026.
//

import Foundation

enum MatchClockStorage {
    static let appGroupIdentifier = "group.com.rgllm.TempoFutebol"
    static let persistenceKey = "matchClock.snapshot"

    static var userDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
}

enum MatchHalf: Int, Codable, Equatable {
    case first = 1
    case second = 2

    var title: String {
        switch self {
        case .first:
            return "1st Half"
        case .second:
            return "2nd Half"
        }
    }

    var next: MatchHalf? {
        switch self {
        case .first:
            return .second
        case .second:
            return nil
        }
    }
}

enum MatchClockStatus: String, Codable, Equatable {
    case ready
    case running
    case paused
    case halfFinished
    case matchFinished

    var title: String {
        switch self {
        case .ready:
            return "Ready"
        case .running:
            return "Running"
        case .paused:
            return "Paused"
        case .halfFinished:
            return "Half-time"
        case .matchFinished:
            return "Finished"
        }
    }
}

enum MatchClockPhase: String, Codable, Equatable {
    case regulation
    case extraTime
}

struct MatchScore: Codable, Equatable {
    var home: Int
    var away: Int

    static let zero = MatchScore(home: 0, away: 0)

    var title: String {
        "\(home)-\(away)"
    }

    var compactTitle: String {
        "H \(home)-\(away) A"
    }
}

struct MatchHapticSettings: Codable, Equatable {
    static let allowedCheckpointMinutes = [10, 20, 30, 40, 45]
    static let standard = MatchHapticSettings(
        checkpointMinutes: allowedCheckpointMinutes,
        extraTimeMinuteAlertsEnabled: true
    )

    var checkpointMinutes: [Int]
    var extraTimeMinuteAlertsEnabled: Bool

    var checkpointSeconds: [Int] {
        normalizedCheckpointMinutes.map { $0 * 60 }
    }

    var normalizedCheckpointMinutes: [Int] {
        checkpointMinutes
            .filter { Self.allowedCheckpointMinutes.contains($0) }
            .uniqued()
            .sorted()
    }

    func isCheckpointMinuteEnabled(_ minute: Int) -> Bool {
        normalizedCheckpointMinutes.contains(minute)
    }

    mutating func setCheckpointMinute(_ minute: Int, isEnabled: Bool) {
        guard Self.allowedCheckpointMinutes.contains(minute) else { return }

        if isEnabled {
            checkpointMinutes = (checkpointMinutes + [minute]).uniqued().sorted()
            return
        }

        checkpointMinutes = checkpointMinutes.filter { $0 != minute }
    }
}

struct MatchSummary: Codable, Equatable {
    let finishedAt: Date
    let score: MatchScore
    let firstHalfDuration: TimeInterval
    let secondHalfDuration: TimeInterval
    let firstHalfAddedTime: TimeInterval
    let secondHalfAddedTime: TimeInterval
    let totalMatchDuration: TimeInterval
    let averageHeartRate: Int?
    let maxHeartRate: Int?
}

struct MatchClockDisplayState {
    let halfTitle: String
    let statusTitle: String
    let isAddedTime: Bool
    let isBreakTimer: Bool
    let isBreakFinished: Bool
    let mainTime: TimeInterval
    let mainLabel: String
    let addedTime: TimeInterval
}

struct PrimaryActionPresentation {
    let title: String
    let iconName: String
    let tintName: String
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

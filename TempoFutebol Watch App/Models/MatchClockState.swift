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

struct MatchClockDisplayState {
    let halfTitle: String
    let statusTitle: String
    let isAddedTime: Bool
    let mainTime: TimeInterval
    let mainLabel: String
    let addedTime: TimeInterval
}

struct PrimaryActionPresentation {
    let title: String
    let iconName: String
    let tintName: String
}

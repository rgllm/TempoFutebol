//
//  MatchHapticPlayer.swift
//  TempoFutebol Watch App
//
//  Created by Codex on 29/04/2026.
//

import WatchKit

enum MatchHapticEvent: Equatable {
    case start
    case timeCheckpoint
    case extraTimeMinute
    case whistle
    case halfTime
    case matchFinished
    case buttonTap
}

protocol MatchHapticPlaying {
    func play(_ event: MatchHapticEvent)
}

struct WatchMatchHapticPlayer: MatchHapticPlaying {
    func play(_ event: MatchHapticEvent) {
        WKInterfaceDevice.current().play(event.watchHapticType)
    }
}

private extension MatchHapticEvent {
    var watchHapticType: WKHapticType {
        switch self {
        case .start:
            return .start
        case .timeCheckpoint:
            return .click
        case .extraTimeMinute:
            return .directionUp
        case .whistle:
            return .success
        case .halfTime:
            return .notification
        case .matchFinished:
            return .notification
        case .buttonTap:
            return .click
        }
    }
}

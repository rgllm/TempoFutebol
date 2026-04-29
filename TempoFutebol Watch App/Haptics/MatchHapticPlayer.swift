//
//  MatchHapticPlayer.swift
//  TempoFutebol Watch App
//
//  Created by Codex on 29/04/2026.
//

import WatchKit

enum MatchHapticEvent: Equatable {
    case start
    case whistle
    case halfTime
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
        case .whistle:
            return .success
        case .halfTime:
            return .notification
        }
    }
}

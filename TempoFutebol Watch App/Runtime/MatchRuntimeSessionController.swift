//
//  MatchRuntimeSessionController.swift
//  TempoFutebol Watch App
//
//  Created by Codex on 03/05/2026.
//

import Foundation
import WatchKit

enum MatchRuntimeSessionStatus: Equatable {
    case inactive
    case starting
    case active
    case expiring
}

struct MatchRuntimeSessionSnapshot: Equatable {
    let status: MatchRuntimeSessionStatus
    let expirationDate: Date?
    let lastInvalidationReason: String?
    let lastErrorDescription: String?

    static let inactive = MatchRuntimeSessionSnapshot(
        status: .inactive,
        expirationDate: nil,
        lastInvalidationReason: nil,
        lastErrorDescription: nil
    )
}

protocol MatchRuntimeSessionControlling: AnyObject {
    var snapshot: MatchRuntimeSessionSnapshot { get }
    var onSnapshotChange: ((MatchRuntimeSessionSnapshot) -> Void)? { get set }

    func startKeepingAppActive()
    func stopKeepingAppActive()
}

@MainActor
final class WatchExtendedRuntimeSessionController: NSObject, MatchRuntimeSessionControlling {
    private var session: WKExtendedRuntimeSession?
    private(set) var snapshot: MatchRuntimeSessionSnapshot = .inactive {
        didSet {
            onSnapshotChange?(snapshot)
        }
    }

    var onSnapshotChange: ((MatchRuntimeSessionSnapshot) -> Void)?

    func startKeepingAppActive() {
        guard session == nil else { return }

        let runtimeSession = WKExtendedRuntimeSession()
        runtimeSession.delegate = self
        session = runtimeSession
        snapshot = MatchRuntimeSessionSnapshot(
            status: .starting,
            expirationDate: nil,
            lastInvalidationReason: nil,
            lastErrorDescription: nil
        )
        runtimeSession.start()
    }

    func stopKeepingAppActive() {
        guard let session else { return }

        self.session = nil
        snapshot = .inactive
        session.invalidate()
    }
}

@MainActor
extension WatchExtendedRuntimeSessionController: WKExtendedRuntimeSessionDelegate {
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        guard extendedRuntimeSession === session else { return }

        snapshot = MatchRuntimeSessionSnapshot(
            status: .active,
            expirationDate: extendedRuntimeSession.expirationDate,
            lastInvalidationReason: nil,
            lastErrorDescription: nil
        )
    }

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        guard extendedRuntimeSession === session else { return }

        snapshot = MatchRuntimeSessionSnapshot(
            status: .expiring,
            expirationDate: extendedRuntimeSession.expirationDate,
            lastInvalidationReason: snapshot.lastInvalidationReason,
            lastErrorDescription: snapshot.lastErrorDescription
        )
    }

    func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        guard extendedRuntimeSession === session else { return }
        session = nil
        snapshot = MatchRuntimeSessionSnapshot(
            status: .inactive,
            expirationDate: extendedRuntimeSession.expirationDate,
            lastInvalidationReason: reason.description,
            lastErrorDescription: error?.localizedDescription
        )
    }
}

private extension WKExtendedRuntimeSessionInvalidationReason {
    var description: String {
        switch self {
        case .none:
            return "none"
        case .sessionInProgress:
            return "session-in-progress"
        case .expired:
            return "expired"
        case .resignedFrontmost:
            return "resigned-frontmost"
        case .suppressedBySystem:
            return "suppressed-by-system"
        case .error:
            return "error"
        @unknown default:
            return "unknown"
        }
    }
}

//
//  HeartRateService.swift
//  TempoFutebol Watch App
//
//  Created by Codex on 30/04/2026.
//

import Combine
import Foundation
import HealthKit

@MainActor
protocol HeartRateProviding: AnyObject, ObservableObject {
    var currentBPM: Int? { get }
    var lastUpdated: Date? { get }

    func requestAuthorization() async
    func startObserving()
    func stopObserving()
}

/// Shared observable surface for live HealthKit reads and preview mocks.
@MainActor
open class HeartRateObservable: ObservableObject, HeartRateProviding {
    @Published private(set) var currentBPM: Int?
    @Published private(set) var lastUpdated: Date?

    init() {}

    open func requestAuthorization() async {}

    open func startObserving() {}

    open func stopObserving() {}

    func applyLatest(bpm: Int?, endDate: Date) {
        currentBPM = bpm
        lastUpdated = endDate
    }
}

/// Reads heart rate samples incrementally via `HKAnchoredObjectQuery` (read-only, no workout session).
@MainActor
final class HeartRateService: HeartRateObservable {
    private let store = HKHealthStore()
    private var query: HKAnchoredObjectQuery?
    private var anchor: HKQueryAnchor?

    override init() {
        super.init()
    }

    override func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }

        do {
            try await store.requestAuthorization(toShare: [], read: [heartRateType])
        } catch {
            // User denied or Health unavailable; UI shows placeholder.
        }
    }

    override func startObserving() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }

        stopObserving()

        let start = Date().addingTimeInterval(-3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: [.strictEndDate])

        let process: @Sendable (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = { [weak self] _, samples, _, newAnchor, error in
            guard let self else { return }
            Task { @MainActor in
                self.handleQueryUpdate(samples: samples, newAnchor: newAnchor, error: error)
            }
        }

        let anchored = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: anchor,
            limit: HKObjectQueryNoLimit,
            resultsHandler: process
        )
        anchored.updateHandler = process

        query = anchored
        store.execute(anchored)
    }

    override func stopObserving() {
        if let query {
            store.stop(query)
        }
        query = nil
    }

    private func ingest(samples: [HKSample]?, unit: HKUnit) {
        guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else { return }

        guard let latest = quantitySamples.max(by: { $0.endDate < $1.endDate }) else { return }

        let bpm = Int(latest.quantity.doubleValue(for: unit).rounded())
        applyLatest(bpm: bpm, endDate: latest.endDate)
    }

    private func handleQueryUpdate(samples: [HKSample]?, newAnchor: HKQueryAnchor?, error: Error?) {
        guard error == nil else { return }

        if let newAnchor {
            anchor = newAnchor
        }

        let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
        ingest(samples: samples, unit: heartRateUnit)
    }
}

#if DEBUG
@MainActor
final class MockHeartRateService: HeartRateObservable {
    private let fixedBPM: Int?

    init(fixedBPM: Int? = 132) {
        self.fixedBPM = fixedBPM
        super.init()
        if let fixedBPM {
            applyLatest(bpm: fixedBPM, endDate: .now)
        }
    }

    override func requestAuthorization() async {}

    override func startObserving() {
        if let fixedBPM {
            applyLatest(bpm: fixedBPM, endDate: .now)
        }
    }

    override func stopObserving() {}
}
#endif

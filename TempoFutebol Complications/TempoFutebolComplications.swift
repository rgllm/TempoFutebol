//
//  TempoFutebolComplications.swift
//  TempoFutebol Complications
//
//  Created by Codex on 29/04/2026.
//

import Foundation
import SwiftUI
import WidgetKit

@main
struct TempoFutebolComplicationsBundle: WidgetBundle {
    var body: some Widget {
        MatchClockComplication()
    }
}

struct MatchClockComplication: Widget {
    private let kind = "TempoFutebolMatchClock"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MatchClockTimelineProvider()) { entry in
            MatchClockComplicationView(entry: entry)
        }
        .configurationDisplayName("TempoFutebol")
        .description("Glance at the current half, time left, and added time.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

struct MatchClockTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> MatchClockEntry {
        MatchClockEntry(date: .now, state: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (MatchClockEntry) -> Void) {
        completion(entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MatchClockEntry>) -> Void) {
        let startDate = Date()
        let entries = makeEntries(from: startDate)
        completion(Timeline(entries: entries, policy: .after(startDate.addingTimeInterval(60))))
    }

    private func makeEntries(from startDate: Date) -> [MatchClockEntry] {
        let current = MatchClockSnapshotStore.load()

        guard current?.status == .running else {
            return [entry(at: startDate)]
        }

        return stride(from: 0, through: 60, by: 1).map { minute in
            entry(at: startDate.addingTimeInterval(TimeInterval(minute * 60)))
        }
    }

    private func entry(at date: Date) -> MatchClockEntry {
        MatchClockEntry(date: date, state: MatchClockComplicationState(snapshot: MatchClockSnapshotStore.load(), at: date))
    }
}

struct MatchClockEntry: TimelineEntry {
    let date: Date
    let state: MatchClockComplicationState
}

struct MatchClockComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MatchClockEntry

    var body: some View {
        switch family {
        case .accessoryCircular, .accessoryCorner:
            circularView
        case .accessoryInline:
            Text("\(entry.state.shortHalf) \(entry.state.timeText)")
        case .accessoryRectangular:
            rectangularView
        default:
            rectangularView
        }
    }

    private var circularView: some View {
        Gauge(value: entry.state.progress) {
            Text(entry.state.shortHalf)
        } currentValueLabel: {
            Text(entry.state.compactTimeText)
                .minimumScaleFactor(0.55)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(entry.state.isAddedTime ? .orange : .green)
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.state.title)
                .font(.headline)

            Text(entry.state.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(entry.state.timeText)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(entry.state.isAddedTime ? .orange : .primary)
        }
        .containerBackground(.clear, for: .widget)
    }
}

struct MatchClockComplicationState {
    static let halfDuration: TimeInterval = 45 * 60

    let title: String
    let subtitle: String
    let shortHalf: String
    let timeText: String
    let compactTimeText: String
    let progress: Double
    let isAddedTime: Bool

    init(snapshot: StoredMatchClockSnapshot?, at date: Date) {
        guard let snapshot else {
            title = "TempoFutebol"
            subtitle = "Ready"
            shortHalf = "--"
            timeText = "45:00"
            compactTimeText = "45"
            progress = 0
            isAddedTime = false
            return
        }

        let elapsed = snapshot.elapsed(at: date)
        let addedTime = max(elapsed - Self.halfDuration, 0)
        let remaining = max(Self.halfDuration - elapsed, 0)
        let halfTitle = snapshot.halfTitle

        title = halfTitle
        shortHalf = snapshot.shortHalfTitle
        isAddedTime = addedTime > 0
        progress = min(max(elapsed / Self.halfDuration, 0), 1)

        switch snapshot.status {
        case .ready:
            subtitle = "Ready"
            timeText = Self.format(Self.halfDuration)
            compactTimeText = "45"
        case .running, .paused:
            subtitle = isAddedTime ? "Added time" : "Time left"
            timeText = isAddedTime ? "+\(Self.format(addedTime))" : Self.format(remaining)
            compactTimeText = isAddedTime ? "+\(Self.compactMinutes(addedTime))" : Self.compactMinutes(remaining)
        case .halfFinished:
            subtitle = "Half-time"
            timeText = "+\(Self.format(addedTime))"
            compactTimeText = "HT"
        case .matchFinished:
            subtitle = "Finished"
            timeText = "+\(Self.format(addedTime))"
            compactTimeText = "FT"
        }
    }

    private static func format(_ interval: TimeInterval) -> String {
        let totalSeconds = max(Int(interval.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        return String(format: "%02d:%02d", minutes, seconds)
    }

    private static func compactMinutes(_ interval: TimeInterval) -> String {
        String(max(Int(ceil(interval / 60)), 0))
    }
}

private extension MatchClockComplicationState {
    static var placeholder: MatchClockComplicationState {
        MatchClockComplicationState(snapshot: nil, at: .now)
    }
}

enum StoredMatchClockStatus: String, Codable {
    case ready
    case running
    case paused
    case halfFinished
    case matchFinished
}

struct StoredMatchClockSnapshot: Codable {
    let half: Int
    let status: StoredMatchClockStatus
    let startedAt: Date?
    let elapsedBeforeStart: TimeInterval

    var halfTitle: String {
        half == 1 ? "1st Half" : "2nd Half"
    }

    var shortHalfTitle: String {
        half == 1 ? "1H" : "2H"
    }

    func elapsed(at date: Date) -> TimeInterval {
        guard status == .running, let startedAt else {
            return elapsedBeforeStart
        }

        return elapsedBeforeStart + date.timeIntervalSince(startedAt)
    }
}

enum MatchClockSnapshotStore {
    static let appGroupIdentifier = "group.com.rgllm.TempoFutebol"
    static let persistenceKey = "matchClock.snapshot"

    static func load() -> StoredMatchClockSnapshot? {
        guard
            let data = userDefaults.data(forKey: persistenceKey),
            let snapshot = try? JSONDecoder().decode(StoredMatchClockSnapshot.self, from: data)
        else {
            return nil
        }

        return snapshot
    }

    private static var userDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
}

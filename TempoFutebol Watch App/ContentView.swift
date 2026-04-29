//
//  ContentView.swift
//  TempoFutebol Watch App
//
//  Created by Rogério Moreira on 29/04/2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var clock = MatchClockViewModel()

    var body: some View {
        Group {
            if clock.shouldTick {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    content(clock.displayState(at: timeline.date))
                }
            } else {
                content(clock.displayState())
            }
        }
    }

    private func content(_ display: MatchClockDisplayState) -> some View {
        VStack(spacing: 8) {
            header(display)

            VStack(spacing: 2) {
                Text(display.mainLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(format(display.mainTime))
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(display.isAddedTime ? .orange : .primary)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            addedTimeRow(display)

            controls
        }
        .padding(.horizontal, 8)
        .scenePadding()
    }

    private func header(_ display: MatchClockDisplayState) -> some View {
        HStack(spacing: 6) {
            Text(display.halfTitle)
                .font(.headline)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(display.statusTitle)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.thinMaterial, in: Capsule())
                .lineLimit(1)
        }
    }

    private func addedTimeRow(_ display: MatchClockDisplayState) -> some View {
        HStack {
            Text("Extra")
                .foregroundStyle(.secondary)

            Spacer()

            Text("+\(format(display.addedTime))")
                .monospacedDigit()
                .foregroundStyle(display.addedTime > 0 ? .orange : .secondary)
        }
        .font(.caption)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button(action: clock.runPrimaryAction) {
                Label(clock.primaryAction.title, systemImage: clock.primaryAction.iconName)
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint(for: clock.primaryAction.tintName))

            Button(action: clock.whistle) {
                Label("Whistle", systemImage: "flag.checkered")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .disabled(!clock.canWhistle)

            Button(role: .destructive, action: clock.resetMatch) {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
        }
        .font(.headline)
    }

    private func tint(for tintName: String) -> Color {
        switch tintName {
        case "yellow":
            return .yellow
        case "green":
            return .green
        default:
            return .accentColor
        }
    }

    private func format(_ interval: TimeInterval) -> String {
        let totalSeconds = max(Int(interval.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

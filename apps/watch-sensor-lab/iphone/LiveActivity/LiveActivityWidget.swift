import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

@main
struct WatchTrackerLiveActivityBundle: WidgetBundle {
    var body: some Widget { WatchTrackerLiveActivityWidget() }
}

struct WatchTrackerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrackerActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.state.phase == "paused" ? "pause.circle.fill" : "location.north.circle.fill")
                    .font(.title2)
                    .foregroundStyle(context.state.phase == "paused" ? .orange : .mint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.activity.uppercased()).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    elapsedView(context.state).font(.title3.weight(.heavy).monospacedDigit())
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(formatDistance(context.state.distanceMeters)).font(.headline.monospacedDigit())
                    HStack(spacing: 7) {
                        Label(context.state.heartRateBPM > 0 ? String(format: "%.0f", context.state.heartRateBPM) : "—", systemImage: "heart.fill")
                        Text(String(format: "%.1f km/h", context.state.speedKPH))
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
            .activityBackgroundTint(.black.opacity(0.86))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.activity, systemImage: "figure.run").font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    elapsedView(context.state).font(.caption.weight(.bold).monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label(formatDistance(context.state.distanceMeters), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        Spacer()
                        Label(context.state.heartRateBPM > 0 ? String(format: "%.0f bpm", context.state.heartRateBPM) : "— bpm", systemImage: "heart.fill")
                        Spacer()
                        Text(String(format: "%.1f km/h", context.state.speedKPH))
                    }
                    .font(.caption)
                }
            } compactLeading: {
                Image(systemName: context.state.phase == "paused" ? "pause.fill" : "figure.run")
            } compactTrailing: {
                elapsedView(context.state).font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: context.state.phase == "paused" ? "pause.fill" : "figure.run")
            }
        }
    }

    @ViewBuilder
    private func elapsedView(_ state: TrackerActivityAttributes.ContentState) -> some View {
        if state.phase == "paused" || state.phase == "ready" {
            Text(formatDuration(state.elapsedSeconds))
        } else {
            let anchor = state.referenceDate.addingTimeInterval(-state.elapsedSeconds)
            Text(timerInterval: anchor...Date.distantFuture, countsDown: false)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%02d:%02d", minutes, secs)
    }

    private func formatDistance(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.2f km", meters / 1000) : String(format: "%.0f m", meters)
    }
}

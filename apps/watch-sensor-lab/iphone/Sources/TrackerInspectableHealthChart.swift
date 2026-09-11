import Charts
import SwiftUI

struct TrackerInspectableHealthChart: View {
    let title: String
    let points: [HealthTrendPoint]
    let accent: Color
    let height: CGFloat

    @State private var selectedDate: Date?

    private var selectedPoint: HealthTrendPoint? {
        guard let selectedDate else { return nil }

        return points.min {
            abs($0.date.timeIntervalSince(selectedDate))
                < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value(title, point.value)
            )
            .foregroundStyle(accent)
            .lineStyle(
                StrokeStyle(
                    lineWidth: 2.5,
                    lineCap: .round,
                    lineJoin: .round
                )
            )

            PointMark(
                x: .value("Date", point.date),
                y: .value(title, point.value)
            )
            .foregroundStyle(accent)
            .symbolSize(
                point.id == selectedPoint?.id
                    ? 75
                    : 18
            )

            if point.id == selectedPoint?.id {
                RuleMark(
                    x: .value("Sélection", point.date)
                )
                .foregroundStyle(.white.opacity(0.45))
                .lineStyle(
                    StrokeStyle(
                        lineWidth: 1,
                        dash: [3, 3]
                    )
                )
                .annotation(
                    position: .top,
                    spacing: 5,
                        overflowResolution: AnnotationOverflowResolution(
                            x: .fit(to: .chart),
                            y: .fit(to: .chart)
                        )
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: 2
                    ) {
                        Text(
                            point.date.formatted(
                                date: .abbreviated,
                                time: .omitted
                            )
                        )
                        .font(.caption2.weight(.black))

                        Text(
                            String(
                                format: "%.1f",
                                point.value
                            )
                        )
                        .font(.caption.weight(.black))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(
                            cornerRadius: 10,
                            style: .continuous
                        )
                    )
                    .allowsHitTesting(false)
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                    .foregroundStyle(.white.opacity(0.06))
                AxisValueLabel()
            }
        }
        .frame(height: height)
    }
}

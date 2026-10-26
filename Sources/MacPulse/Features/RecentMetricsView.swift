import Charts
import SwiftUI

struct RecentMetricsView: View {
    @EnvironmentObject private var model: DashboardModel
    @EnvironmentObject private var localization: LocalizationStore
    @State private var showMemory = false

    var body: some View {
        SurfaceCard {
            AdaptiveStack {
                Text(localization.workflow(.recentActivity)).font(.headline).frame(
                    maxWidth: .infinity, alignment: .leading)
                Picker(localization.workflow(.recentActivity), selection: $showMemory) {
                    Text(localization.text(.cpu)).tag(false)
                    Text(localization.text(.memoryState)).tag(true)
                }.pickerStyle(.segmented).frame(maxWidth: 280)
            }
            Text(showMemory ? localization.workflow(.memoryAvailablePercent) : "CPU (%)")
                .font(.caption).foregroundStyle(.secondary)
            let points = model.metricHistory.filter { value($0) != nil }
            if points.count < 2 {
                Text(localization.workflow(.collectingSamples)).font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 110)
            } else {
                Chart(points) { point in
                    if let value = value(point) {
                        AreaMark(x: .value("Time", point.date), yStart: .value("Baseline", 0), yEnd: .value("%", value))
                            .foregroundStyle(.tint.opacity(0.08))
                        LineMark(x: .value("Time", point.date), y: .value("%", value))
                            .foregroundStyle(.tint).lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(values: [0, 50, 100]) }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .frame(height: 130)
                .accessibilityLabel(
                    showMemory ? localization.workflow(.memoryAvailablePercent) : localization.text(.cpu))
            }
        }
    }

    private func value(_ point: MetricHistoryPoint) -> Double? { showMemory ? point.availableMemory : point.cpu }
}

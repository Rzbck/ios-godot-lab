import SwiftUI

struct ProgressionEntryView: View {
    @AppStorage("tracker.healthInsightsEnabled") private var healthInsightsEnabled = false
    @State private var showRecentVolume = false

    var body: some View {
        PerformanceProgressionTodayView()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showRecentVolume = true
                    } label: {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                    }
                    .accessibilityLabel("Ouvrir le volume récent")
                }
            }
            .sheet(isPresented: $showRecentVolume) {
                TrainingVolumeInsightView()
            }
            .onAppear {
                healthInsightsEnabled = true
            }
    }
}

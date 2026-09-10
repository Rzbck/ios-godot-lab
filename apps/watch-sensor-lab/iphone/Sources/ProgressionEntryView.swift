import SwiftUI

struct ProgressionEntryView: View {
    @AppStorage("tracker.healthInsightsEnabled") private var healthInsightsEnabled = false

    var body: some View {
        HealthProgressionDashboardView()
            .onAppear {
                healthInsightsEnabled = true
            }
    }
}

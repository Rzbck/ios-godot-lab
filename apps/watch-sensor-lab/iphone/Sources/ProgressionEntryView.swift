import SwiftUI

struct ProgressionEntryView: View {
    @AppStorage("tracker.healthInsightsEnabled") private var healthInsightsEnabled = false
    @State private var showRecentVolume = false
    @State private var showRecoveryLab = false

    var body: some View {
        PerformanceProgressionTodayView()
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        showRecentVolume = true
                    } label: {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                    }
                    .accessibilityLabel("Ouvrir le volume récent")

                    Button {
                        showRecoveryLab = true
                    } label: {
                        Image(systemName: "sparkles")
                    }
                    .accessibilityLabel("Ouvrir le laboratoire récupération")
                }
            }
            .sheet(isPresented: $showRecentVolume) {
                TrainingVolumeInsightView()
            }
            .sheet(isPresented: $showRecoveryLab) {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 14) {
                            TrackerRecoveryIntelligenceCard()
                            TrackerPhysiologyProfileCard()
                        }
                        .padding(16)
                    }
                    .background(
                        LinearGradient(
                            colors: [.cyan.opacity(0.08), .indigo.opacity(0.08), .black],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .ignoresSafeArea()
                    )
                    .navigationTitle("Récupération")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .preferredColorScheme(.dark)
            }
            .onAppear {
                healthInsightsEnabled = true
            }
    }
}

import SwiftUI

struct ProgressionEntryView: View {
    @AppStorage("tracker.healthInsightsEnabled") private var healthInsightsEnabled = false
    @State private var showRecentVolume = false
    @State private var showTrainingLoad = false
    @State private var showRecoveryLab = false
    @State private var showMatchedActivities = false

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
                        showTrainingLoad = true
                    } label: {
                        Image(systemName: "square.grid.2x2.fill")
                    }
                    .accessibilityLabel("Ouvrir la charge multi-source")

                    Button {
                        showRecoveryLab = true
                    } label: {
                        Image(systemName: "sparkles")
                    }
                    .accessibilityLabel("Ouvrir le laboratoire récupération")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showMatchedActivities = true
                    } label: {
                        Image(systemName: "square.stack.3d.up.fill")
                    }
                    .accessibilityLabel("Ouvrir les séances similaires")
                }
            }
            .sheet(isPresented: $showRecentVolume) {
                TrainingVolumeInsightView()
            }
            .sheet(isPresented: $showTrainingLoad) {
                TrainingLoadIntelligenceView()
            }
            .sheet(isPresented: $showMatchedActivities) {
                MatchedActivityComparisonView()
            }
            .sheet(isPresented: $showRecoveryLab) {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 14) {
                            TrackerRecoveryIntelligenceCard()
                            TrackerDailyBriefCard()
                            TrackerSleepLabEntryCard()
                            TrackerCorrelationLabEntryCard()
                            TrackerBehaviorJournalEntryCard()
                            TrackerNightVitalsCard()
                            TrackerCardioFitnessCard()
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

import SwiftUI

// Historical repair v2 candidate: CI/device artifact is required before hardware use.
/// Historical HealthKit mutation is intentionally iPhone-only.
///
/// Live workouts remain Watch-owned. Apple documents standalone
/// HKWorkoutBuilder for iOS while watchOS workout recording must use
/// HKWorkoutSession + HKLiveWorkoutBuilder. The Watch therefore exposes only
/// the recovery status/entry point and never reconstructs historical workouts.
struct WatchRestoreEntryPage: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("RÉCUPÉRATION")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
            }

            Spacer(minLength: 0)

            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.orange)

            Text("Réparation historique sur iPhone")
                .font(.caption.weight(.bold))
                .multilineTextAlignment(.center)

            Text("Ouvre Watch Tracker sur l’iPhone puis Récupération. La Watch reste l’autorité uniquement pour les séances en direct.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)

            Label("iPhone · Récupération", systemImage: "wrench.and.screwdriver.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 4)
    }
}

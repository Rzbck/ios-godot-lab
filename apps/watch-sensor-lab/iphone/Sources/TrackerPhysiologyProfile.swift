import Foundation
import HealthKit
import SwiftUI

struct TrackerPhysiologyReading: Equatable {
    let value: Double
    let date: Date
    let source: String
}

struct TrackerPhysiologyProfile: Equatable {
    let ageYears: Int?
    let bodyMassKG: TrackerPhysiologyReading?
    let heightCM: TrackerPhysiologyReading?
    let vo2Max: TrackerPhysiologyReading?
    let heartRateRecoveryOneMinute: TrackerPhysiologyReading?
    let ageEstimatedMaxHeartRateBPM: Double?
    let generatedAt: Date

    var absoluteVO2LitersPerMinute: Double? {
        guard let vo2 = vo2Max?.value,
              let mass = bodyMassKG?.value,
              vo2 > 0,
              mass > 0 else { return nil }
        return vo2 * mass / 1000
    }

    var completeness: Double {
        let fields: [Bool] = [
            ageYears != nil,
            bodyMassKG != nil,
            heightCM != nil,
            vo2Max != nil,
            heartRateRecoveryOneMinute != nil,
        ]
        return Double(fields.filter { $0 }.count) / Double(fields.count)
    }
}

final class TrackerPhysiologyProfileReader {
    private let store = HKHealthStore()
    private let calendar = Calendar.autoupdatingCurrent

    func load(completion: @escaping (TrackerPhysiologyProfile) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async { completion(Self.emptyProfile()) }
            return
        }

        var readTypes = Set<HKObjectType>()
        let identifiers: [HKQuantityTypeIdentifier] = [
            .bodyMass,
            .height,
            .vo2Max,
            .heartRateRecoveryOneMinute,
        ]
        for identifier in identifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                readTypes.insert(type)
            }
        }
        if let birthDate = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) {
            readTypes.insert(birthDate)
        }

        store.requestAuthorization(toShare: [], read: readTypes) { [weak self] _, _ in
            guard let self else { return }
            self.loadAuthorized(completion: completion)
        }
    }

    private func loadAuthorized(completion: @escaping (TrackerPhysiologyProfile) -> Void) {
        let now = Date()
        let age = readAge(now: now)
        let group = DispatchGroup()
        let lock = NSLock()
        var bodyMass: TrackerPhysiologyReading?
        var height: TrackerPhysiologyReading?
        var vo2: TrackerPhysiologyReading?
        var recovery: TrackerPhysiologyReading?

        if let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            group.enter()
            loadLatest(type: type, unit: .gramUnit(with: .kilo)) { value in
                lock.lock(); bodyMass = value; lock.unlock(); group.leave()
            }
        }

        if let type = HKQuantityType.quantityType(forIdentifier: .height) {
            group.enter()
            loadLatest(type: type, unit: .meterUnit(with: .centi)) { value in
                lock.lock(); height = value; lock.unlock(); group.leave()
            }
        }

        if let type = HKQuantityType.quantityType(forIdentifier: .vo2Max) {
            group.enter()
            let milliliters = HKUnit.literUnit(with: .milli)
            let kilograms = HKUnit.gramUnit(with: .kilo)
            let vo2Unit = milliliters.unitDivided(by: kilograms).unitDivided(by: .minute())
            loadLatest(type: type, unit: vo2Unit) { value in
                lock.lock(); vo2 = value; lock.unlock(); group.leave()
            }
        }

        if let type = HKQuantityType.quantityType(forIdentifier: .heartRateRecoveryOneMinute) {
            group.enter()
            loadLatest(type: type, unit: .count()) { value in
                lock.lock(); recovery = value; lock.unlock(); group.leave()
            }
        }

        group.notify(queue: .main) {
            let estimatedMax: Double?
            if let age, age >= 18, age <= 100 {
                estimatedMax = 208.0 - (0.7 * Double(age))
            } else {
                estimatedMax = nil
            }

            completion(
                TrackerPhysiologyProfile(
                    ageYears: age,
                    bodyMassKG: bodyMass,
                    heightCM: height,
                    vo2Max: vo2,
                    heartRateRecoveryOneMinute: recovery,
                    ageEstimatedMaxHeartRateBPM: estimatedMax,
                    generatedAt: now
                )
            )
        }
    }

    private func readAge(now: Date) -> Int? {
        guard let components = try? store.dateOfBirthComponents(),
              let birthDate = calendar.date(from: components) else { return nil }
        let value = calendar.dateComponents([.year], from: birthDate, to: now).year
        guard let value, value >= 0, value <= 120 else { return nil }
        return value
    }

    private func loadLatest(
        type: HKQuantityType,
        unit: HKUnit,
        completion: @escaping (TrackerPhysiologyReading?) -> Void
    ) {
        guard type.is(compatibleWith: unit) else {
            completion(nil)
            return
        }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: type,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sort]
        ) { _, samples, _ in
            guard let sample = samples?.first as? HKQuantitySample,
                  sample.quantity.is(compatibleWith: unit) else {
                completion(nil)
                return
            }
            let value = sample.quantity.doubleValue(for: unit)
            guard value.isFinite else {
                completion(nil)
                return
            }
            completion(
                TrackerPhysiologyReading(
                    value: value,
                    date: sample.endDate,
                    source: sample.sourceRevision.source.name
                )
            )
        }
        store.execute(query)
    }

    private static func emptyProfile() -> TrackerPhysiologyProfile {
        TrackerPhysiologyProfile(
            ageYears: nil,
            bodyMassKG: nil,
            heightCM: nil,
            vo2Max: nil,
            heartRateRecoveryOneMinute: nil,
            ageEstimatedMaxHeartRateBPM: nil,
            generatedAt: Date()
        )
    }
}

struct TrackerPhysiologyProfileCard: View {
    @State private var profile: TrackerPhysiologyProfile?
    @State private var loading = true

    private let reader = TrackerPhysiologyProfileReader()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PROFIL PHYSIOLOGIQUE")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    Text("Contexte pour tes calculs")
                        .font(.headline.weight(.bold))
                }
                Spacer()
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.cyan)
            }

            if let profile {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    profileCell("ÂGE", profile.ageYears.map { "\($0) ans" } ?? "—", "calendar", .cyan)
                    profileCell("POIDS", profile.bodyMassKG.map { String(format: "%.1f kg", $0.value) } ?? "—", "scalemass.fill", .mint)
                    profileCell("TAILLE", profile.heightCM.map { String(format: "%.0f cm", $0.value) } ?? "—", "ruler.fill", .indigo)
                    profileCell("VO₂ MAX", profile.vo2Max.map { String(format: "%.1f", $0.value) } ?? "—", "lungs.fill", .orange)
                    profileCell("RÉCUP. FC 1 MIN", profile.heartRateRecoveryOneMinute.map { String(format: "%.0f bpm", $0.value) } ?? "—", "heart.circle.fill", .pink)
                    profileCell("FC MAX · ÂGE", profile.ageEstimatedMaxHeartRateBPM.map { String(format: "%.0f bpm", $0) } ?? "—", "heart.text.square.fill", .purple)
                }

                VStack(alignment: .leading, spacing: 5) {
                    if let estimated = profile.ageEstimatedMaxHeartRateBPM {
                        Text("FC max estimée par âge : \(Int(estimated.rounded())) bpm")
                            .font(.caption.weight(.semibold))
                        Text("Fallback adulte uniquement. Une FC max personnelle mesurée ou saisie reste prioritaire, car une formule d’âge peut être largement différente de la valeur individuelle réelle.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let vo2 = profile.vo2Max {
                        Text("VO₂ max Apple Health : \(String(format: "%.1f", vo2.value)) mL/kg/min")
                            .font(.caption.weight(.semibold))
                        if let absolute = profile.absoluteVO2LitersPerMinute {
                            Text("Équivalent absolu dérivé : ~\(String(format: "%.2f", absolute)) L/min. La tendance principale reste le VO₂ relatif fourni par Health.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                ProgressView(value: profile.completeness)
                    .tint(.cyan)
                Text("Profil Health lisible à \(Int((profile.completeness * 100).rounded()))%. Les valeurs manquantes restent manquantes : elles ne sont pas inventées.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if loading {
                ProgressView("Lecture du profil Santé…")
                    .font(.caption)
            } else {
                Text("Aucune donnée de profil Santé lisible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .task { refresh() }
    }

    private func profileCell(_ title: String, _ value: String, _ symbol: String, _ accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol)
                .foregroundStyle(accent)
            Text(value)
                .font(.headline.weight(.black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(title)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .padding(10)
        .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func refresh() {
        loading = true
        reader.load { value in
            profile = value
            loading = false
        }
    }
}

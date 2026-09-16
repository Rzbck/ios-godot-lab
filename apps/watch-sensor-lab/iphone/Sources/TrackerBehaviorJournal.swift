import Foundation
import SwiftUI

struct TrackerJournalBehavior: Identifiable, Hashable {
    let id: String
    let title: String
    let shortTitle: String
    let symbol: String
    let category: String
    let accent: Color

    static let defaults: [TrackerJournalBehavior] = [
        .init(id: "late_caffeine", title: "Caféine tardive", shortTitle: "Caféine", symbol: "cup.and.saucer.fill", category: "Soir", accent: .orange),
        .init(id: "alcohol", title: "Alcool", shortTitle: "Alcool", symbol: "wineglass.fill", category: "Soir", accent: .pink),
        .init(id: "late_meal", title: "Repas tardif", shortTitle: "Repas tardif", symbol: "fork.knife", category: "Soir", accent: .orange),
        .init(id: "late_screen", title: "Écran tardif", shortTitle: "Écran tardif", symbol: "iphone", category: "Soir", accent: .blue),
        .init(id: "meditation", title: "Méditation / respiration", shortTitle: "Méditation", symbol: "brain.head.profile", category: "Récupération", accent: .purple),
        .init(id: "sauna", title: "Sauna / chaleur", shortTitle: "Sauna", symbol: "flame.fill", category: "Récupération", accent: .red),
        .init(id: "mobility", title: "Mobilité / étirements", shortTitle: "Mobilité", symbol: "figure.cooldown", category: "Récupération", accent: .mint),
        .init(id: "good_hydration", title: "Hydratation soignée", shortTitle: "Hydratation", symbol: "drop.fill", category: "Habitudes", accent: .cyan),
        .init(id: "nap", title: "Sieste", shortTitle: "Sieste", symbol: "powersleep", category: "Habitudes", accent: .indigo),
        .init(id: "high_stress", title: "Stress élevé ressenti", shortTitle: "Stress élevé", symbol: "bolt.heart.fill", category: "Contexte", accent: .orange),
        .init(id: "travel", title: "Voyage / déplacement", shortTitle: "Voyage", symbol: "airplane", category: "Contexte", accent: .blue),
        .init(id: "sick_feeling", title: "Sensation de maladie", shortTitle: "Pas en forme", symbol: "thermometer.medium", category: "Contexte", accent: .pink),
    ]
}

struct TrackerJournalDay: Codable, Equatable {
    let dayStart: TimeInterval
    var selectedBehaviorIDs: Set<String>
    var note: String
    var updatedAt: TimeInterval

    var date: Date { Date(timeIntervalSince1970: dayStart) }
}

final class TrackerBehaviorJournalStore: ObservableObject {
    static let shared = TrackerBehaviorJournalStore()

    @Published private(set) var days: [TrackerJournalDay] = []

    private let defaultsKey = "tracker.behaviorJournal.v1"
    private let calendar = Calendar.autoupdatingCurrent

    private init() {
        load()
    }

    func entry(for date: Date) -> TrackerJournalDay {
        let start = calendar.startOfDay(for: date).timeIntervalSince1970
        return days.first(where: { abs($0.dayStart - start) < 1 })
            ?? TrackerJournalDay(dayStart: start, selectedBehaviorIDs: [], note: "", updatedAt: 0)
    }

    func isSelected(_ behaviorID: String, on date: Date) -> Bool {
        entry(for: date).selectedBehaviorIDs.contains(behaviorID)
    }

    func toggle(_ behaviorID: String, on date: Date) {
        var value = entry(for: date)
        if value.selectedBehaviorIDs.contains(behaviorID) {
            value.selectedBehaviorIDs.remove(behaviorID)
        } else {
            value.selectedBehaviorIDs.insert(behaviorID)
        }
        value.updatedAt = Date().timeIntervalSince1970
        upsert(value)
    }

    func setNote(_ note: String, on date: Date) {
        var value = entry(for: date)
        value.note = String(note.prefix(400))
        value.updatedAt = Date().timeIntervalSince1970
        upsert(value)
    }

    func countDays(behaviorID: String, withinLastDays count: Int) -> Int {
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -(count - 1), to: today) ?? .distantPast
        return days.filter { day in
            day.date >= start && day.selectedBehaviorIDs.contains(behaviorID)
        }.count
    }

    func loggedDays(withinLastDays count: Int) -> Int {
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -(count - 1), to: today) ?? .distantPast
        return days.filter { $0.date >= start && $0.updatedAt > 0 }.count
    }

    private func upsert(_ value: TrackerJournalDay) {
        if let index = days.firstIndex(where: { abs($0.dayStart - value.dayStart) < 1 }) {
            days[index] = value
        } else {
            days.append(value)
        }
        days.sort { $0.dayStart < $1.dayStart }
        if days.count > 365 {
            days = Array(days.suffix(365))
        }
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([TrackerJournalDay].self, from: data) else {
            days = []
            return
        }
        days = decoded.sorted { $0.dayStart < $1.dayStart }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(days) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

struct TrackerBehaviorJournalEntryCard: View {
    @ObservedObject private var store = TrackerBehaviorJournalStore.shared

    var body: some View {
        NavigationLink {
            TrackerBehaviorJournalView()
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "book.pages.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.purple)
                    .frame(width: 48, height: 48)
                    .background(.purple.opacity(0.13), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("JOURNAL · EXPÉRIENCES")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.purple)
                    Text("Construire tes propres découvertes")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("\(store.loggedDays(withinLastDays: 30)) jours renseignés sur les 30 derniers")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(15)
            .background(.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct TrackerBehaviorJournalView: View {
    @ObservedObject private var store = TrackerBehaviorJournalStore.shared
    @State private var selectedDate = Date()
    @State private var note = ""

    private var grouped: [(String, [TrackerJournalBehavior])] {
        let order = ["Soir", "Récupération", "Habitudes", "Contexte"]
        return order.compactMap { category in
            let values = TrackerJournalBehavior.defaults.filter { $0.category == category }
            return values.isEmpty ? nil : (category, values)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 15) {
                intro
                dateSelector

                ForEach(grouped, id: \.0) { category, behaviors in
                    VStack(alignment: .leading, spacing: 9) {
                        Text(category.uppercased())
                            .font(.caption.weight(.black))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(behaviors) { behavior in
                                behaviorButton(behavior)
                            }
                        }
                    }
                    .journalPanel()
                }

                noteSection
                progressSection
                privacySection
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                colors: [.purple.opacity(0.10), .indigo.opacity(0.05), .black],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reloadNote() }
        .onChange(of: selectedDate) { _, _ in reloadNote() }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Mini-expériences personnelles", systemImage: "flask.fill")
                .font(.title3.weight(.black))
                .foregroundStyle(.purple)
            Text("Marque simplement ce qui s’est passé. Ces tags ne modifient aucun score. Ils servent uniquement à construire, avec le temps, des associations personnelles affichées avec leur taille d’échantillon.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .journalPanel()
    }

    private var dateSelector: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("JOUR À RENSEIGNER")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            DatePicker(
                "Jour",
                selection: $selectedDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
        }
        .journalPanel()
    }

    private func behaviorButton(_ behavior: TrackerJournalBehavior) -> some View {
        let selected = store.isSelected(behavior.id, on: selectedDate)
        return Button {
            store.toggle(behavior.id, on: selectedDate)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: behavior.symbol)
                    .foregroundStyle(selected ? Color.white : behavior.accent)
                Text(behavior.shortTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.white : Color.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .padding(.horizontal, 10)
            .background(
                selected ? behavior.accent : behavior.accent.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(behavior.title), \(selected ? "sélectionné" : "non sélectionné")")
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTE · OPTIONNELLE")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            TextField("Contexte libre, 400 caractères max", text: $note, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.plain)
                .padding(11)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button("Enregistrer la note") {
                store.setNote(note, on: selectedDate)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        }
        .journalPanel()
    }

    private var progressSection: some View {
        let logged = store.loggedDays(withinLastDays: 30)
        return VStack(alignment: .leading, spacing: 9) {
            Text("MATIÈRE POUR LES DÉCOUVERTES")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(logged) / 14")
                        .font(.title3.weight(.black))
                        .monospacedDigit()
                    Text("jours renseignés récents")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ProgressView(value: Double(min(logged, 14)), total: 14)
                    .tint(.purple)
                    .frame(width: 110)
            }
            Text("Tracker attendra suffisamment de jours et, pour une comparaison oui/non, suffisamment d’occurrences des deux côtés avant d’afficher un impact. Le journal commence donc par collecter proprement, pas par conclure vite.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .journalPanel()
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Local et explicite", systemImage: "lock.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.mint)
            Text("Ces entrées sont conservées localement dans Watch Tracker. Elles ne sont pas écrites dans Apple Health et ne modifient ni l’Indice Tracker, ni les données d’entraînement.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 2)
    }

    private func reloadNote() {
        note = store.entry(for: selectedDate).note
    }
}

private extension View {
    func journalPanel() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

import Foundation
import HealthKit

enum ActivityKind: String, CaseIterable, Identifiable, Codable {
    case automatic
    case walking, running, hiking, cycling
    case swimming, rowing, paddleSports, sailing, surfingSports, underwaterDiving, waterFitness, waterPolo, waterSports
    case elliptical, stairClimbing, stairs, stepTraining, jumpRope
    case functionalStrengthTraining, traditionalStrengthTraining, coreTraining, crossTraining, mixedCardio, highIntensityIntervalTraining
    case flexibility, preparationAndRecovery, cooldown, barre, cardioDance, socialDance, yoga, mindAndBody, pilates, taiChi
    case boxing, kickboxing, martialArts, wrestling
    case badminton, pickleball, racquetball, squash, tableTennis, tennis
    case basketball, soccer, americanFootball, australianFootball, baseball, cricket, discSports, handball, hockey, lacrosse, rugby, softball, volleyball
    case archery, bowling, fencing, gymnastics, trackAndField
    case climbing, equestrianSports, fishing, golf, hunting, play
    case crossCountrySkiing, curling, downhillSkiing, snowSports, snowboarding, skatingSports
    case wheelchairWalkPace, wheelchairRunPace, handCycling, fitnessGaming, swimBikeRun
    case other

    var id: String { rawValue }
    var isAutomatic: Bool { self == .automatic }

    var label: String {
        switch self {
        case .automatic: return "Auto"
        case .walking: return "Marche"
        case .running: return "Course"
        case .hiking: return "Randonnée"
        case .cycling: return "Vélo"
        case .swimming: return "Natation"
        case .rowing: return "Aviron"
        case .paddleSports: return "Paddle / Kayak"
        case .sailing: return "Voile"
        case .surfingSports: return "Surf"
        case .underwaterDiving: return "Plongée"
        case .waterFitness: return "Aquafitness"
        case .waterPolo: return "Water-polo"
        case .waterSports: return "Sports nautiques"
        case .elliptical: return "Elliptique"
        case .stairClimbing: return "Stepper"
        case .stairs: return "Escaliers"
        case .stepTraining: return "Step"
        case .jumpRope: return "Corde à sauter"
        case .functionalStrengthTraining: return "Musculation fonctionnelle"
        case .traditionalStrengthTraining: return "Musculation"
        case .coreTraining: return "Gainage"
        case .crossTraining: return "Cross training"
        case .mixedCardio: return "Cardio mixte"
        case .highIntensityIntervalTraining: return "HIIT"
        case .flexibility: return "Souplesse"
        case .preparationAndRecovery: return "Échauffement / récupération"
        case .cooldown: return "Retour au calme"
        case .barre: return "Barre"
        case .cardioDance: return "Danse cardio"
        case .socialDance: return "Danse"
        case .yoga: return "Yoga"
        case .mindAndBody: return "Corps et esprit"
        case .pilates: return "Pilates"
        case .taiChi: return "Tai-chi"
        case .boxing: return "Boxe"
        case .kickboxing: return "Kick-boxing"
        case .martialArts: return "Arts martiaux"
        case .wrestling: return "Lutte"
        case .badminton: return "Badminton"
        case .pickleball: return "Pickleball"
        case .racquetball: return "Racquetball"
        case .squash: return "Squash"
        case .tableTennis: return "Tennis de table"
        case .tennis: return "Tennis"
        case .basketball: return "Basket"
        case .soccer: return "Football"
        case .americanFootball: return "Football américain"
        case .australianFootball: return "Football australien"
        case .baseball: return "Baseball"
        case .cricket: return "Cricket"
        case .discSports: return "Disc sports"
        case .handball: return "Handball"
        case .hockey: return "Hockey"
        case .lacrosse: return "Lacrosse"
        case .rugby: return "Rugby"
        case .softball: return "Softball"
        case .volleyball: return "Volley"
        case .archery: return "Tir à l’arc"
        case .bowling: return "Bowling"
        case .fencing: return "Escrime"
        case .gymnastics: return "Gymnastique"
        case .trackAndField: return "Athlétisme"
        case .climbing: return "Escalade"
        case .equestrianSports: return "Équitation"
        case .fishing: return "Pêche"
        case .golf: return "Golf"
        case .hunting: return "Chasse"
        case .play: return "Jeu"
        case .crossCountrySkiing: return "Ski de fond"
        case .curling: return "Curling"
        case .downhillSkiing: return "Ski alpin"
        case .snowSports: return "Sports de neige"
        case .snowboarding: return "Snowboard"
        case .skatingSports: return "Patinage"
        case .wheelchairWalkPace: return "Fauteuil allure marche"
        case .wheelchairRunPace: return "Fauteuil allure course"
        case .handCycling: return "Handbike"
        case .fitnessGaming: return "Fitness gaming"
        case .swimBikeRun: return "Triathlon"
        case .other: return "Autre"
        }
    }

    var symbol: String {
        switch self {
        case .automatic: return "wand.and.stars"
        case .walking: return "figure.walk"
        case .running: return "figure.run"
        case .hiking: return "figure.hiking"
        case .cycling, .handCycling: return "bicycle"
        case .swimming, .waterFitness, .waterPolo, .waterSports, .underwaterDiving: return "figure.pool.swim"
        case .rowing, .paddleSports: return "figure.rower"
        case .sailing, .surfingSports: return "water.waves"
        case .elliptical: return "figure.elliptical"
        case .stairClimbing, .stairs, .stepTraining: return "figure.stairs"
        case .jumpRope: return "figure.jumprope"
        case .functionalStrengthTraining, .traditionalStrengthTraining, .coreTraining: return "dumbbell.fill"
        case .crossTraining, .mixedCardio, .highIntensityIntervalTraining: return "figure.cross.training"
        case .flexibility, .preparationAndRecovery, .cooldown, .barre, .yoga, .mindAndBody, .pilates, .taiChi: return "figure.mind.and.body"
        case .cardioDance, .socialDance: return "figure.dance"
        case .boxing, .kickboxing, .martialArts, .wrestling: return "figure.boxing"
        case .badminton, .pickleball, .racquetball, .squash, .tableTennis, .tennis: return "tennis.racket"
        case .basketball: return "basketball.fill"
        case .soccer: return "soccerball"
        case .americanFootball, .australianFootball, .rugby: return "football.fill"
        case .baseball, .softball: return "baseball.fill"
        case .cricket: return "cricket.ball.fill"
        case .discSports: return "circle.dashed"
        case .handball: return "hand.raised.fill"
        case .hockey: return "hockey.puck.fill"
        case .lacrosse: return "sportscourt"
        case .volleyball: return "volleyball.fill"
        case .archery: return "scope"
        case .bowling: return "figure.bowling"
        case .fencing: return "figure.fencing"
        case .gymnastics: return "figure.gymnastics"
        case .trackAndField: return "figure.track.and.field"
        case .climbing: return "figure.climbing"
        case .equestrianSports: return "figure.equestrian.sports"
        case .fishing: return "fish.fill"
        case .golf: return "figure.golf"
        case .hunting: return "binoculars.fill"
        case .play, .fitnessGaming: return "gamecontroller.fill"
        case .crossCountrySkiing, .downhillSkiing, .snowSports: return "figure.skiing.crosscountry"
        case .curling: return "circle.fill"
        case .snowboarding: return "figure.snowboarding"
        case .skatingSports: return "figure.skating"
        case .wheelchairWalkPace, .wheelchairRunPace: return "figure.roll"
        case .swimBikeRun: return "figure.run.square.stack"
        case .other: return "figure.mixed.cardio"
        }
    }

    var healthKitType: HKWorkoutActivityType {
        switch self {
        case .automatic: return .mixedCardio
        case .walking: return .walking
        case .running: return .running
        case .hiking: return .hiking
        case .cycling: return .cycling
        case .swimming: return .swimming
        case .rowing: return .rowing
        case .paddleSports: return .paddleSports
        case .sailing: return .sailing
        case .surfingSports: return .surfingSports
        case .underwaterDiving: return .underwaterDiving
        case .waterFitness: return .waterFitness
        case .waterPolo: return .waterPolo
        case .waterSports: return .waterSports
        case .elliptical: return .elliptical
        case .stairClimbing: return .stairClimbing
        case .stairs: return .stairs
        case .stepTraining: return .stepTraining
        case .jumpRope: return .jumpRope
        case .functionalStrengthTraining: return .functionalStrengthTraining
        case .traditionalStrengthTraining: return .traditionalStrengthTraining
        case .coreTraining: return .coreTraining
        case .crossTraining: return .crossTraining
        case .mixedCardio: return .mixedCardio
        case .highIntensityIntervalTraining: return .highIntensityIntervalTraining
        case .flexibility: return .flexibility
        case .preparationAndRecovery: return .preparationAndRecovery
        case .cooldown: return .cooldown
        case .barre: return .barre
        case .cardioDance: return .cardioDance
        case .socialDance: return .socialDance
        case .yoga: return .yoga
        case .mindAndBody: return .mindAndBody
        case .pilates: return .pilates
        case .taiChi: return .taiChi
        case .boxing: return .boxing
        case .kickboxing: return .kickboxing
        case .martialArts: return .martialArts
        case .wrestling: return .wrestling
        case .badminton: return .badminton
        case .pickleball: return .pickleball
        case .racquetball: return .racquetball
        case .squash: return .squash
        case .tableTennis: return .tableTennis
        case .tennis: return .tennis
        case .basketball: return .basketball
        case .soccer: return .soccer
        case .americanFootball: return .americanFootball
        case .australianFootball: return .australianFootball
        case .baseball: return .baseball
        case .cricket: return .cricket
        case .discSports: return .discSports
        case .handball: return .handball
        case .hockey: return .hockey
        case .lacrosse: return .lacrosse
        case .rugby: return .rugby
        case .softball: return .softball
        case .volleyball: return .volleyball
        case .archery: return .archery
        case .bowling: return .bowling
        case .fencing: return .fencing
        case .gymnastics: return .gymnastics
        case .trackAndField: return .trackAndField
        case .climbing: return .climbing
        case .equestrianSports: return .equestrianSports
        case .fishing: return .fishing
        case .golf: return .golf
        case .hunting: return .hunting
        case .play: return .play
        case .crossCountrySkiing: return .crossCountrySkiing
        case .curling: return .curling
        case .downhillSkiing: return .downhillSkiing
        case .snowSports: return .snowSports
        case .snowboarding: return .snowboarding
        case .skatingSports: return .skatingSports
        case .wheelchairWalkPace: return .wheelchairWalkPace
        case .wheelchairRunPace: return .wheelchairRunPace
        case .handCycling: return .handCycling
        case .fitnessGaming: return .fitnessGaming
        case .swimBikeRun: return .swimBikeRun
        case .other: return .other
        }
    }

    init?(healthKitType: HKWorkoutActivityType) {
        guard let match = Self.allCases.first(where: { !$0.isAutomatic && $0.healthKitType == healthKitType }) else { return nil }
        self = match
    }
}


enum TrackerFinishDisposition: String, Codable {
    /// Conserve les changements d'activité détectés pendant la séance.
    case preserveDetectedSegments

    /// L'utilisateur confirme que toute la séance doit être considérée
    /// comme un seul sport.
    case forceSingleActivity
}

struct TrackerFinishReviewState {
    let required: Bool
    let suggestedActivity: ActivityKind
}

enum TrackerWorkflowPolicy {
    static func finishReview(
        selectedActivity: ActivityKind,
        effectiveActivity: ActivityKind,
        suggestedActivity: ActivityKind? = nil
    ) -> TrackerFinishReviewState {
        TrackerFinishReviewState(
            required: selectedActivity.isAutomatic,
            suggestedActivity: suggestedActivity ?? effectiveActivity
        )
    }
}


/// Fonctions de session qui doivent exister sur iPhone ET Apple Watch.
///
/// Ajouter une nouvelle fonction commune ici oblige les deux modèles
/// à l'implémenter, sinon la target concernée ne compile plus.
enum TrackerSharedWorkflowCapability: String, CaseIterable {
    case activitySelection
    case start
    case autoPauseToggle
    case pause
    case resume
    case finishReview
    case finishDisposition
    case purge
    case historicalActivityCorrection
}

protocol TrackerSharedWorkflowSurface: AnyObject {
    var workflowIsRunning: Bool { get }
    var workflowIsPaused: Bool { get }
    var workflowSelectedActivity: ActivityKind { get }
    var workflowEffectiveActivity: ActivityKind { get }
    var workflowFinishReview: TrackerFinishReviewState { get }

    func workflowSelectActivity(_ activity: ActivityKind)
    func workflowSetAutoPauseEnabled(_ enabled: Bool)

    func workflowStart()
    func workflowPause()
    func workflowResume()

    func workflowFinish(
        disposition: TrackerFinishDisposition,
        finalActivity: ActivityKind?
    )

    func workflowDeleteAllTestData()

    func workflowCorrectHistoricalActivity(
        sessionID: String,
        activity: ActivityKind
    )
}


// Paquet compact et durable construit depuis les raw Tracker iPhone,
// puis transféré à la Watch. Les logs motion complets ne traversent
// jamais WatchConnectivity : seuls les éléments nécessaires à la
// reconstruction Santé sont transportés.
struct TrackerHealthRestoreHeartRate: Codable, Equatable {
    let timestamp: TimeInterval
    let bpm: Double
}

struct TrackerHealthRestoreLocation: Codable, Equatable {
    let timestamp: TimeInterval
    let latitude: Double
    let longitude: Double
    let altitudeMeters: Double
    let horizontalAccuracyMeters: Double
    let verticalAccuracyMeters: Double
    let speedMps: Double?
}

struct TrackerHealthRestorePause: Codable, Equatable {
    let startedAt: TimeInterval
    let endedAt: TimeInterval
}

struct TrackerHealthRestorePayload: Codable, Equatable {
    static let currentSchema = 1

    let schema: Int
    let sessionID: String
    let targetActivity: String
    let sourceActivity: String
    let startedAt: TimeInterval
    let endedAt: TimeInterval
    let activeDuration: TimeInterval
    let distanceMeters: Double
    let activeEnergyKcal: Double?
    let heartRates: [TrackerHealthRestoreHeartRate]
    let locations: [TrackerHealthRestoreLocation]
    let pauses: [TrackerHealthRestorePause]
    let pauseProvenance: String
    let sourceBuildSHA: String?
    let sourceAlgorithmVersion: String?
}


struct TrackerWireMessage: Codable {
    enum Kind: String, Codable { case authority, request, selection, purge }

    var schema = 3
    var kind: Kind
    var command: String?
    var sessionID: String
    var revision: Int64
    var selectionRevision: Int64
    var selectedActivity: String
    var effectiveActivity: String
    var phase: String?
    var purgeID: String
    var timestamp: TimeInterval
    var startedAt: TimeInterval?
    var elapsedSeconds: Double?
    var distanceMeters: Double?
    var speedMps: Double?
    var altitudeMeters: Double?
    var elevationGainMeters: Double?
    var elevationLossMeters: Double?
    var heartRateBPM: Double?
    var averageHeartRateBPM: Double?
    var activeEnergyKcal: Double?

    // Workflow de fin partagé iPhone / Watch.
    var finishReviewRequired: Bool? = nil
    var suggestedFinalActivity: String? = nil
    var finishDisposition: String? = nil
    var finalActivityOverride: String? = nil
}

enum TrackerWireCodec {
    static func encode(_ message: TrackerWireMessage) -> Data? { try? JSONEncoder().encode(message) }
    static func decode(_ data: Data) -> TrackerWireMessage? { try? JSONDecoder().decode(TrackerWireMessage.self, from: data) }
}

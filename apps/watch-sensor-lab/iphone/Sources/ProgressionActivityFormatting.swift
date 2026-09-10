import Foundation

func activityLabel(_ raw: String) -> String {
    ActivityKind(rawValue: raw)?.label ?? raw
}

func activitySymbol(_ raw: String) -> String {
    ActivityKind(rawValue: raw)?.symbol ?? "figure.mixed.cardio"
}

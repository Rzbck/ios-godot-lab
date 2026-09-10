import Foundation

func progressionActivityLabel(_ raw: String) -> String {
    ActivityKind(rawValue: raw)?.label ?? raw
}

func progressionActivitySymbol(_ raw: String) -> String {
    ActivityKind(rawValue: raw)?.symbol ?? "figure.mixed.cardio"
}

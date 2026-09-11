import HealthKit

/// Centralises HealthKit quantity conversion so an incompatible unit
/// is treated as unavailable data instead of raising NSException.
extension HKQuantity {
    func trackerDoubleValue(for unit: HKUnit) -> Double? {
        guard self.is(compatibleWith: unit) else { return nil }
        let value = doubleValue(for: unit)
        return value.isFinite ? value : nil
    }
}

enum TrackerHealthUnits {
    /// HealthKit VO2 max dimension: volume / mass / time.
    /// Compose it explicitly instead of parsing a unit string.
    static let vo2Max: HKUnit = {
        let milliliters = HKUnit.literUnit(with: .milli)
        let kilograms = HKUnit.gramUnit(with: .kilo)
        return milliliters
            .unitDivided(by: kilograms)
            .unitDivided(by: .minute())
    }()
}

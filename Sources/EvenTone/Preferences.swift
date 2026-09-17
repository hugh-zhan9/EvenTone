import Foundation

final class Preferences {
    private let defaults: UserDefaults
    private let trimsKey = "deviceTrims.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var processingEnabled: Bool {
        get { (defaults.object(forKey: "processingEnabled") as? NSNumber)?.boolValue ?? false }
        set { defaults.set(newValue, forKey: "processingEnabled") }
    }

    var volume: Double {
        get {
            guard let number = defaults.object(forKey: "outputVolume") as? NSNumber else { return 0.8 }
            return Self.clean(number.doubleValue, range: 0...1, fallback: 0.8)
        }
        set { defaults.set(Self.clean(newValue, range: 0...1, fallback: 0.8), forKey: "outputVolume") }
    }

    var automatic: Bool {
        get { (defaults.object(forKey: "automaticLeveling") as? NSNumber)?.boolValue ?? true }
        set { defaults.set(newValue, forKey: "automaticLeveling") }
    }

    func trim(for uid: String) -> Double {
        let raw = (defaults.dictionary(forKey: trimsKey)?[uid] as? NSNumber)?.doubleValue ?? 0
        return Self.clean(raw, range: -12...12, fallback: 0)
    }

    func setTrim(_ value: Double, for uid: String) {
        guard !uid.isEmpty else { return }
        var values = defaults.dictionary(forKey: trimsKey) ?? [:]
        values[uid] = Self.clean(value, range: -12...12, fallback: 0)
        defaults.set(values, forKey: trimsKey)
    }

    private static func clean(_ value: Double, range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}

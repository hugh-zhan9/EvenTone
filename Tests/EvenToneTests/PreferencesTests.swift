import Foundation

final class PreferencesTests {
    func testProcessingStateStartsOffAndPersistsBothChoices() throws {
        let suite = "EvenToneTests.\(UUID().uuidString)"
        let defaults = try unwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = Preferences(defaults: defaults)
        expectFalse(first.processingEnabled)
        first.processingEnabled = true
        let second = Preferences(defaults: try unwrap(UserDefaults(suiteName: suite)))
        expectTrue(second.processingEnabled)
        second.processingEnabled = false
        expectFalse(Preferences(defaults: try unwrap(UserDefaults(suiteName: suite))).processingEnabled)
        defaults.set("invalid", forKey: "processingEnabled")
        expectFalse(first.processingEnabled)
    }

    func testIndependentDevicesPersistAndNewDeviceStartsNeutral() throws {
        let suite = "EvenToneTests.\(UUID().uuidString)"
        let defaults = try unwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = Preferences(defaults: defaults)
        expectEqual(first.volume, 0.8)
        expectTrue(first.automatic)
        first.setTrim(5.5, for: "airpods")
        first.setTrim(-3, for: "wired")
        first.volume = 0.6
        first.automatic = false
        let reloaded = Preferences(defaults: defaults)
        expectEqual(reloaded.trim(for: "airpods"), 5.5)
        expectEqual(reloaded.trim(for: "wired"), -3)
        expectEqual(reloaded.trim(for: "new-device"), 0)
        expectEqual(reloaded.volume, 0.6)
        expectFalse(reloaded.automatic)
    }

    func testCorruptAndOutOfRangeSettingsCannotBecomeExtremeGain() throws {
        let suite = "EvenToneTests.\(UUID().uuidString)"
        let defaults = try unwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = Preferences(defaults: defaults)
        settings.volume = .nan
        expectEqual(settings.volume, 0.8)
        settings.volume = 9
        expectEqual(settings.volume, 1)
        settings.setTrim(.infinity, for: "a")
        expectEqual(settings.trim(for: "a"), 0)
        settings.setTrim(99, for: "a")
        expectEqual(settings.trim(for: "a"), 12)
        defaults.set(["a": "broken"], forKey: "deviceTrims.v1")
        expectEqual(settings.trim(for: "a"), 0)
    }
}

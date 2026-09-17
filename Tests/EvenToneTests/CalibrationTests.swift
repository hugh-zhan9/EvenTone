import Foundation

final class CalibrationTests {
    func testFailedTargetPlaybackCanBeRetriedWithoutLosingDraft() {
        var session = CalibrationSession(referenceUID: "reference", referenceName: "Reference headphones", referenceTrim: 4, volume: 0.3)
        session.selectTarget(uid: "target", trim: 5)
        session.markPlayed(.reference); session.markPlayed(.target)
        session.adjust(.quieter)
        session.preparePlayback(.target) // Start a request which may fail before markPlayed.
        expectFalse(session.canCompare)
        expectTrue(session.heardReference)
        expectEqual(session.targetUID, "target")
        expectEqual(session.referenceName, "Reference headphones")
        expectEqual(session.draftTrim, 7)
        session.preparePlayback(.target)
        session.markPlayed(.target) // Reconnected device; same session and candidate.
        expectTrue(session.canCompare)
        expectEqual(session.draftTrim, 7)
    }

    func testReferenceReplayMustSucceedBeforeSaving() throws {
        let suite = "EvenToneTests.\(UUID().uuidString)"
        let defaults = try unwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        preferences.setTrim(1, for: "target")
        var session = CalibrationSession(referenceUID: "reference", referenceName: "Reference headphones", referenceTrim: 0, volume: 0.3)
        session.selectTarget(uid: "target", trim: 5)
        session.markPlayed(.reference); session.markPlayed(.target)
        session.preparePlayback(.reference)
        expectTrue(session.heardTarget)
        expectFalse(session.save(to: preferences))
        expectEqual(preferences.trim(for: "target"), 1)
        session.markPlayed(.reference)
        // Save is based on completed auditions, without an online-device query.
        expectTrue(session.save(to: preferences))
        expectEqual(preferences.trim(for: "target"), 5)
    }

    func testDraftIsOnlyPersistedOnExplicitSave() throws {
        let suite = "EvenToneTests.\(UUID().uuidString)"
        let defaults = try unwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        preferences.setTrim(4, for: "reference")
        preferences.setTrim(-2, for: "target")
        preferences.setTrim(3, for: "other")
        preferences.volume = 0.3
        preferences.processingEnabled = true
        var session = CalibrationSession(referenceUID: "reference", referenceName: "Reference headphones", referenceTrim: 4, volume: 0.3)
        session.selectTarget(uid: "target", trim: -2)
        session.markPlayed(.reference); session.markPlayed(.target)
        session.adjust(.quieter)
        expectEqual(session.draftTrim, 0)
        expectEqual(preferences.trim(for: "target"), -2)
        expectFalse(session.save(to: preferences)) // Must audition the adjusted candidate.
        session.markPlayed(.target)
        expectTrue(session.save(to: preferences))
        expectEqual(preferences.trim(for: "target"), 0)
        expectEqual(preferences.trim(for: "reference"), 4)
        expectEqual(preferences.trim(for: "other"), 3)
        expectEqual(preferences.volume, 0.3)
        expectTrue(preferences.processingEnabled)
    }

    func testCancelAndFailedPlaybackLeaveStoredCompensationUntouched() throws {
        let suite = "EvenToneTests.\(UUID().uuidString)"
        let defaults = try unwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        preferences.setTrim(5, for: "target")
        var session = CalibrationSession(referenceUID: "reference", referenceName: "Reference headphones", referenceTrim: 0, volume: 0.5)
        session.selectTarget(uid: "target", trim: 5)
        session.markPlayed(.reference); session.markPlayed(.target)
        session.adjust(.louder)
        session.markPlayed(.target)
        expectTrue(session.canCompare)
        expectEqual(preferences.trim(for: "target"), 5) // Dropping the draft is a no-op.
        session.preparePlayback(.target)
        expectFalse(session.save(to: preferences))
        expectEqual(preferences.trim(for: "target"), 5)
        expectEqual(session.targetUID, "target")
        expectEqual(session.referenceName, "Reference headphones")
    }

    func testOnlyTwoDifferentAuditionedDevicesCanMatch() {
        var session = CalibrationSession(referenceUID: "reference", referenceName: "Reference headphones", referenceTrim: 0, volume: 0.5)
        session.markPlayed(.reference); session.markPlayed(.target)
        expectFalse(session.canCompare)
        session.selectTarget(uid: "reference", trim: 0)
        expectTrue(session.targetUID == nil)
        session.selectTarget(uid: "target", trim: 0)
        expectFalse(session.canCompare)
        session.markPlayed(.target)
        expectTrue(session.canCompare)
        session.selectTarget(uid: "another", trim: 6)
        expectFalse(session.canCompare)
        expectTrue(session.heardReference)
        expectEqual(session.draftTrim, 6)
    }

    func testFeedbackDirectionRefinesAndStaysWithinLimits() {
        var session = CalibrationSession(referenceUID: "reference", referenceName: "Reference headphones", referenceTrim: 0, volume: 0.5)
        session.selectTarget(uid: "target", trim: 0)
        session.markPlayed(.reference); session.markPlayed(.target)
        session.adjust(.louder)
        expectEqual(session.draftTrim, -2)
        session.markPlayed(.target); session.adjust(.quieter)
        expectEqual(session.step, 1)
        expectEqual(session.draftTrim, -1)
        session.markPlayed(.target); session.adjust(.louder)
        expectEqual(session.step, 0.5)
        expectEqual(session.draftTrim, -1.5)
        for _ in 0..<100 { session.markPlayed(.target); session.adjust(.quieter) }
        expectEqual(session.draftTrim, 12)
        expectTrue(session.atLimit)
        for _ in 0..<100 { session.markPlayed(.target); session.adjust(.louder) }
        expectEqual(session.draftTrim, -12)
        session.selectTarget(uid: "another", trim: 0)
        expectEqual(session.step, 2)
    }

    func testReferenceSignalIsRepeatableFadedAndPeakBounded() {
        let first = ReferenceSignal.samples()
        expectEqual(first.count, 48_000 * 6)
        expectEqual(first, ReferenceSignal.samples())
        expectEqual(first.first, 0)
        expectEqual(first.last, 0)
        expectTrue(first.allSatisfy { $0.isFinite && abs($0) < 0.891251 })
        let rms = sqrt(first.reduce(0.0) { $0 + Double($1 * $1) } / Double(first.count))
        let actual = rms * Double(ReferenceSignal.playbackVolume(volume: 1, trim: 0))
        expectTrue(actual > 0.035 && actual < 0.045)
    }

    func testReferenceVolumeMatchesNormalCompensationRatios() {
        let base = ReferenceSignal.playbackVolume(volume: 0.3, trim: 0)
        let boosted = ReferenceSignal.playbackVolume(volume: 0.3, trim: 6)
        expectTrue(abs(boosted / base - pow(10, 6.0 / 20)) < 0.0001)
        expectEqual(ReferenceSignal.playbackVolume(volume: 1, trim: 12), 1)
        expectEqual(ReferenceSignal.playbackVolume(volume: 0, trim: 12), 0)
        expectEqual(ReferenceSignal.playbackVolume(volume: .nan, trim: 0), 0)
    }

    func testReferenceWaveContainsFiniteDurationStereoPCM() {
        let wav = ReferenceSignal.wav()
        expectEqual(String(data: wav[0..<4], encoding: .ascii), "RIFF")
        expectEqual(String(data: wav[8..<12], encoding: .ascii), "WAVE")
        expectEqual(wav.count, 44 + 48_000 * 6 * 4)
        expectEqual(wav[22], 2) // stereo
        expectEqual(wav[34], 16) // PCM16
        for index in stride(from: 44, to: wav.count, by: 4) {
            expectEqual(wav[index], wav[index + 2])
            expectEqual(wav[index + 1], wav[index + 3])
        }
    }
}

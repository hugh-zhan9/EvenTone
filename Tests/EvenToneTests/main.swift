import Foundation

setbuf(stdout, nil)
let dsp = DSPTests()
let preferences = PreferencesTests()
let outputSelection = OutputSelectionTests()
let login = LoginItemTests()
let calibration = CalibrationTests()
let cases: [(String, () throws -> Void)] = [
    ("Quiet and loud videos converge", dsp.testQuietAndLoudVideosConverge),
    ("Sudden loud input is limited and settles", dsp.testQuietToLoudTransitionStaysUnderCeilingAndSettles),
    ("Silence and low noise do not accumulate boost", dsp.testSilenceAndVeryLowNoiseDoNotAccumulateBoost),
    ("Manual calibration and output volume", dsp.testManualCalibrationAndVolumeWhenAutomaticDisabled),
    ("Limiter preserves stereo ratio", dsp.testLimiterPreservesStereoRatio),
    ("Invalid values, empty, single frame and mono", dsp.testInvalidNumbersEmptySingleFrameAndMono),
    ("Maximum gain and zero volume", dsp.testGainLimitAndZeroVolume),
    ("Tap mapping skips microphone and writes planar output", dsp.testIOMapsTapAfterDisabledMicrophoneAndPlanarOutput),
    ("Mismatched buffers produce silence and a fault", dsp.testIORejectsMismatchedBuffersWithSilence),
    ("Independent device preferences survive reload", preferences.testIndependentDevicesPersistAndNewDeviceStartsNeutral),
    ("Processing switch persists on and off across reload", preferences.testProcessingStateStartsOffAndPersistsBothChoices),
    ("Invalid preferences cannot become extreme gain", preferences.testCorruptAndOutOfRangeSettingsCannotBecomeExtremeGain),
    ("Device switch waits for read-back and completes once", outputSelection.testWaitsForConfirmationAndCompletesOnce),
    ("Immediate and already-selected output confirmation", outputSelection.testSynchronousConfirmationAndAlreadySelectedDevice),
    ("Unconfirmed output selection times out without retry", outputSelection.testUnconfirmedSwitchTimesOutWithoutRetryOrRollback),
    ("Empty default and delayed notification at deadline", outputSelection.testMissingDefaultCanBeReplacedAndLateConfirmationAtDeadline),
    ("Output switch native failures stay visible", outputSelection.testReadRequestAndListenerErrorsAreNotSuccess),
    ("Login item register/unregister uses system state", login.testRegistrationAndCancellationReadBackSystemStatus),
    ("Login item errors preserve actual registration state", login.testFailedOperationsKeepActualSystemState),
    ("Pending login approval is explicit and can be cancelled", login.testRequiresApprovalDoesNotClaimEffectiveOrRegisterAgain),
    ("Login item refresh and relaunch see external settings", login.testRefreshAndRelaunchRespectExternalChanges),
    ("Calibration saves only the auditioned target on confirmation", calibration.testDraftIsOnlyPersistedOnExplicitSave),
    ("Calibration cancellation and failed playback preserve stored trim", calibration.testCancelAndFailedPlaybackLeaveStoredCompensationUntouched),
    ("Calibration requires two different auditioned devices", calibration.testOnlyTwoDifferentAuditionedDevicesCanMatch),
    ("Calibration feedback refines within compensation limits", calibration.testFeedbackDirectionRefinesAndStaysWithinLimits),
    ("Reference signal is repeatable, faded and peak bounded", calibration.testReferenceSignalIsRepeatableFadedAndPeakBounded),
    ("Reference gain matches normal compensation ratios", calibration.testReferenceVolumeMatchesNormalCompensationRatios),
    ("Reference WAV is finite stereo PCM", calibration.testReferenceWaveContainsFiniteDurationStereoPCM),
    ("Failed target playback can be retried without losing the draft", calibration.testFailedTargetPlaybackCanBeRetriedWithoutLosingDraft),
    ("Reference replay must succeed before saving", calibration.testReferenceReplayMustSucceedBeforeSaving)
]
for (name, run) in cases {
    try run()
    print("PASS \(name)")
}
print("\(cases.count) tests passed")

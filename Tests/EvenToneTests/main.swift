import Foundation

setbuf(stdout, nil)
let dsp = DSPTests()
let preferences = PreferencesTests()
let outputSelection = OutputSelectionTests()
let login = LoginItemTests()
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
    ("Login item refresh and relaunch see external settings", login.testRefreshAndRelaunchRespectExternalChanges)
]
for (name, run) in cases {
    try run()
    print("PASS \(name)")
}
print("\(cases.count) tests passed")

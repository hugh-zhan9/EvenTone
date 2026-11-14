import Foundation

setbuf(stdout, nil)
let bluetooth = BluetoothCallTests()
let dsp = DSPTests()
let preferences = PreferencesTests()
let outputSelection = OutputSelectionTests()
let login = LoginItemTests()
let calibration = CalibrationTests()
let applicationMute = ApplicationMuteTests()
let cases: [(String, () throws -> Void)] = [
    ("Call mute target follows recovered device and rejects ended calls", bluetooth.testCallTargetIsReadAfterStartupRecoveryAndRejectsMusicMode),
    ("Call mute experiment defaults off and persists", preferences.testCallMutingExperimentDefaultsOffAndPersists),
    ("Call mute tap preserves selected process and device scope", bluetooth.testCallMuteDescriptionTargetsOnlySelectedProcessesAndDevice),
    ("Call passthrough keeps application control active without DSP", bluetooth.testPassthroughKeepsApplicationControlActiveWithoutDSP),
    ("Startup call transitions preserve intent only after confirmed cleanup", bluetooth.testTransitionDuringStartupPreservesIntentOnlyAfterCleanup),
    ("Bluetooth call mode is distinguished from music and wired outputs", bluetooth.testOnlyClassicBluetoothCommunicationRatesBypass),
    ("Bluetooth calls bypass native capture and release processing", bluetooth.testCallBypassesNativeStartupEvenWithInvalidDevice),
    ("Application mute covers all devices and output streams", applicationMute.testMuteCoversAllOutputStreams),
    ("Partial native mute failures clean up and survive stale UI responses", applicationMute.testPartialRoutingFailureCleansAndStaysVisible),
    ("Native mute transition orders suppression and exclusion", applicationMute.testRoutingTransitionOrderAndNoOp),
    ("Browser helpers group without merging distinct applications", applicationMute.testBrowserHelpersAndDistinctApps),
    ("Applications mute independently and clear for a new session", applicationMute.testIndependentMuteRestoreAndClear),
    ("Mute follows process turnover and remains removable while idle", applicationMute.testProcessTurnoverAndIdleSelection),
    ("Failed HAL update never commits the selected mute state", applicationMute.testFailureDoesNotCommitSelection),
    ("Quiet and loud videos converge", dsp.testQuietAndLoudVideosConverge),
    ("Sudden loud input is limited and settles", dsp.testQuietToLoudTransitionStaysUnderCeilingAndSettles),
    ("Silence and low noise do not accumulate boost", dsp.testSilenceAndVeryLowNoiseDoNotAccumulateBoost),
    ("Manual calibration and output volume", dsp.testManualCalibrationAndVolumeWhenAutomaticDisabled),
    ("Limiter preserves stereo ratio", dsp.testLimiterPreservesStereoRatio),
    ("Invalid values, empty, single frame and mono", dsp.testInvalidNumbersEmptySingleFrameAndMono),
    ("Maximum gain and zero volume", dsp.testGainLimitAndZeroVolume),
    ("Physical input slots must be disabled and match the advertised layout", dsp.testIORetainedPhysicalInputsMustBeDisabledAndComplete),
    ("Tap mapping supports omitted six-channel physical input", dsp.testIOMapsCompactTapAfterSixDisabledChannels),
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

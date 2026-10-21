# Spec 0013 requirement-to-evidence matrix

This is an implementation inventory, not a `Validated` or release approval.
`Automated` means an executable check exists; each revision still needs a passing
run. `Partial` and `Pending` identify evidence that cannot be replaced by a build.
Repository-relative paths below resolve from the product repository root.

The current iPhone device-test iteration was accepted by the user on 2026-10-21
with its three recorded exceptions; see
`ReleaseEvidence/spec-0013/2026-10-21-tactile-iphone17pro/acceptance.json`.
Further device runs are not required for that acceptance. Remaining evidence in
this matrix describes broader validation, not a request to repeat the accepted session.

| Requirement | Status | Concrete test/evidence | Remaining evidence |
| --- | --- | --- | --- |
| QK-TST-001 | Partial | This matrix maps all 18 requirements and 3 acceptance criteria | Independent requirement/evidence review before Validated |
| QK-TST-002 | Automated | `TestingAndEvaluationTests.testIndependentTokenizerOracleMatchesEveryTokenIDAndMask`; `CoreMLRuntimeTests.testExactTokenizerAndInputTensorsAgainstGolden`; protected `CurrentModelContractTests.testSwiftTokenizerMatchesIndependentGoldenCorpus` | Full licensed vocabulary uses the protected tier |
| QK-TST-003 | Automated | `CoreMLRuntimeTests.testActualCoreMLOutputsMatchIndependentArithmeticReference` and `testPublicModelsProduceReferenceObservationsEndToEnd`; `Tools/CoreMLFixtures/reference.py` | Official model on its pinned protected toolchain |
| QK-TST-004 | Automated | `.github/workflows/coreml-runtime.yml`, all three `Packages/QualiaCoreML/Tests/QualiaCoreMLTests/Resources/CoreML/*-v2` models | CI run for this revision |
| QK-TST-005 | Partial | `.github/workflows/protected-model-parity.yml`; `Tools/ModelContract/reference_inference.py --verify`; `CurrentModelContractTests` | Provision trusted runner, environment reviewers, pinned toolchain and licensed assets; execute job |
| QK-TST-006 | Automated | `TestingAndEvaluationTests.testDeterministicEndToEndCommandsMatchVersionedStory`; `Tests/Fixtures/testing-v1/session.json` | Explicit review of independent literal expectations |
| QK-TST-007 | Automated | `TestingPrimitivesTests.testClockReleasesOnlyDueSleepersAndRejectsBackwardsTime`; `testClockCancellationBeforeAndAfterRegistrationAndTeardown`; migrated `AnalysisRuntimeTests` cancellation waits; existing injected-time scene/heartbeat tests | None for the new path |
| QK-TST-008 | Automated | `TestingAndEvaluationTests.testControlledStaleAndResetCompletionsCannotChangeSession`; `SessionOrchestrationTests` MainActor-delay, reset and shared-session tests; `TestingPrimitivesTests` request-number/cancellation tests | None for the new path |
| QK-TST-009 | Automated / review | Transition map; `HeartbeatBranchAuditTests`; `Tools/TestingFixtures/heartbeat_coverage.py`; `Evaluation/coverage/heartbeat-audit.json` | Review two invariant-trap exceptions; Swift exports regions but no branch counters, so no numeric 100% branch claim |
| QK-TST-010 | Automated / manual | `NarrativeEvidenceTests.test_physical_checklist_cannot_be_replaced_by_simulator_or_partial_evidence`; `evidence.py physical` | Completed physical-device matrix |
| QK-TST-011 | Partial | `Tools/TestingFixtures/generate.py` exact regeneration and refusal to overwrite; existing fixture checksum inventories; documented isolated new-version review | Explicit fixture review and repository protection settings |
| QK-TST-012 | Automated / manual | `NarrativeEvidenceTests.test_complete_synthetic_bundle_passes_without_claiming_experience_quality`; `Evaluation/cards/current-status.md` | Real separate semantic and experience reports |
| QK-TST-013 | Implemented / data pending | `study.py` dataset/prediction validation and hard-negative metrics; `test_metrics.py`; `evidence.py` admission | Licensed/sanitized production-like narrative dataset and evaluation |
| QK-TST-014 | Implemented / data pending | `study.py freeze/evaluate`: validation-only cost selection, split-leakage checks, hash-bound protocol, exclusive evaluation lock; `StudyTests` | Reviewed real split freeze and validation-only threshold selection records |
| QK-TST-015 | Automated | `evidence.py regression`; `NarrativeEvidenceTests.test_regression_metadata_is_mandatory`; `Tests/Fixtures/Regression/session-lifecycle-v1.json` | Curate future confirmed failures before corpus entry |
| QK-TST-016 | Automated / infrastructure | Acceptance/gate tests propagate errors and reject missing test discovery; public model CI runs actual inference; protected preflight exits nonzero for absent assets; tautological softmax/range-only/permanently empty legacy tests removed | Protected runner must be available; legacy asset-backed skips in public CI are not parity success |
| QK-TST-017 | Automated | New fixtures are deterministic literals (`manifest.json`: `seed: null`); no randomized sampling introduced | Future randomized runs must store/report fixed seeds |
| QK-TST-018 | Implemented / validation pending | v1 iPhone records; v2 build-bound A/B/C ratings and background confirmation (`ReleaseEvidence/spec-0013/2026-10-21-tactile-iphone17pro`); separate real RuBERT load; `run.py`, `summarize.py`, physical validator | Remaining v2 preference/accessibility/general sustained checks, device matrix and candidate-specific release review |
| AC-0013-001 | Automated | `TestingAndEvaluationTests.testIndependentTokenizerOracleMatchesEveryTokenIDAndMask` | None for public vocabulary tier |
| AC-0013-002 | Automated | `TestingAndEvaluationTests.testDeterministicEndToEndCommandsMatchVersionedStory` | Physical feeling remains a separate gate |
| AC-0013-003 | Automated | `TestingAndEvaluationTests.testNarrativeCapabilityEvidenceGateAndFixtureRegeneration`; `NarrativeEvidenceTests.test_each_missing_report_blocks_narrative_claim` | No real candidate is admitted by synthetic tests |

## Heartbeat transition map

All names below belong to `HeartbeatEffectTests` in
`Tests/QualiaKitTests/Heartbeat/`. This maps meaningful transitions and guards;
it does not claim instrumented 100% source branch coverage.

| Transition / guard | Existing test |
| --- | --- |
| Idle → running with fresh confidence | `testFreshConfidentEvidenceStartsBoundedOwnedHeartbeat` |
| Idle suppressed on missing/low/unrelated evidence | `testMissingLowAndUnrelatedConfidenceCannotStart` |
| Running stable / hysteresis | `testHysteresisAndInsignificantChangesDoNotRecreatePlayer` |
| Running update / throttled update / original deadline | `testSignificantUpdateIsThrottledAndDoesNotRenewDeadline` |
| Running → resolving → cooldown → idle | `testResolvingStopsAndCooldownPreventsRestart` |
| Running → cooldown at maximum duration | `testMaximumDurationStopsEvenAtHighTension` |
| Physical expiry without observation | `testRecordingDeadlineExpiresWithoutAnotherObservation` |
| Time jump past running/resolving and cooldown | `testRunningAdvancesPastElapsedCooldownAndUsesFirstFreshEvidence`, `testResolvingAdvancesPastElapsedCooldownAndUsesFirstFreshEvidence` |
| Fresh evidence after time jump | `testTimeJumpStillRequiresFreshEvidenceAndHonorsUnelapsedCooldown` |
| Failed → suppressed until reset | `testFailureDoesNotRetryUntilExplicitReset`, `testFailureDuringResolveDoesNotRetryAndResetStillStopsOldPattern` |
| Invalid restored lifecycle → failed | `testRestoredAppliedStateWithoutLifecycleCannotRenewPlayback` |
| Policy intensity zero / independent accent | `testPolicyScaleZeroStopsWhileStillPermittingAccent` |
| Reset/background/disable invalidation | `testResetAndBackgroundInvalidateQueuedUpdateAndOnlyStopOwner`, `testDisableInvalidatesPendingWorkWithoutAnotherObservation` |
| Cleanup failure / retry / owner isolation | `testLifecycleCleansPlayerAfterStartAndRollbackFail`, `testResetReportsPendingCleanupFailureAndRetainsStateUntilCleanupSucceeds`, `testOwnerResetDoesNotTouchAnotherOwnersActiveOrPendingPlayers` |
| Engine reset and interruption | `testEngineResetAndInterruptionDoNotRestartHeartbeat` |

## External evidence and review still required

Before calling spec 0013 complete: obtain independent API/fixture review, review the
reachable-region audit and invariant exceptions, run protected official-model parity for the candidate revision,
freeze and evaluate a real narrative dataset, establish release-build performance
baselines with variance and concurrency recorded, and perform physical-device
and experience studies. Metric computation, validation-only threshold selection, split validation and a
one-attempt evaluation lock are implemented in `study.py`/`metrics.py`. Paired
experience aggregation is in `experience.py`; the v2 device lab has recorded
one holder's A/B/C comfort/distinguishability and background results, with the
remaining checks listed in the evidence status card. Real independent annotations, model
predictions and reviewer decisions must be supplied; local files cannot establish
chronology across copied study directories or authenticate human independence.

## Added branch-audit cases

`testIdleBelowThresholdAndNonMonotonicRunningTimeDoNotDispatch` covers cold
below-threshold and reversed running time;
`testDefensiveMissingParametersDoesNotInventAReplacement` covers a malformed
restored running state; `testWeightedThreatAndUrgencyCanDriveWithoutSuspenseValue`
covers weighted alternative drivers and absent state values. The measured
reachable-region audit leaves only constructor invariant traps uncovered. The
exception set is tied to source text and SHA-256, and CI fails on any additional
uncovered nonfatal region.

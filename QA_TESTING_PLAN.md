# BabyMont Production Testing Plan

This plan demonstrates coverage across the BabyMont architecture: models, services, view models, SwiftUI views, tab navigation, local database storage, APNs backend payloads, ML model pipeline, and end-to-end UX behaviours.

## Automated Test Matrix

| Layer | Coverage | Location |
| --- | --- | --- |
| Models | `BabyEvent`, category/severity typing, metadata encoding, severity ordering | `BabyMontTests/BabyMontTests.swift` |
| Local database | in-memory event store order and fetch limits | `BabyMontTests/BabyMontTests.swift` |
| Rule engine | crying, sustained noise, stillness, high temperature, humidity, duplicate cooldowns | `BabyMontTests/BabyMontTests.swift` |
| View model | start/stop monitoring, manual critical alert, push/watch/home/cloud coordination | `BabyMontTests/BabyMontTests.swift` |
| Notifications | APNs payload shape, critical interruption level, collapse identifier | `BabyMontTests/BabyMontTests.swift` |
| UI and tabs | Monitor, Events, Rules, Settings tab navigation and primary actions | `BabyMontUITests/BabyMontUITests.swift` |
| Backend | APNs payload and header generation without live Apple network calls | `apns_provider/tests/test_main.py` |
| ML pipeline | Core ML model generation/validation | `.github/workflows/train_cry_model.yml` and `ml/run_model_pipeline.sh` |
| Xcode CI | app build, test bundle build, timed simulator tests, optional UI tests | `.github/workflows/xcode_ci.yml` |

## Manual QA Scenarios

### 1. Launch and Navigation
1. Launch BabyMont.
2. Confirm the Monitor tab opens with the title `BabyMont`.
3. Tap `Events`, `Rules`, and `Settings`.
4. Confirm every tab shows its navigation title and expected controls.

Expected result: all tabs are reachable, no blank screens, and no layout overlap on iPhone and iPad simulator sizes.

### 2. Local Monitoring Flow
1. Open the Monitor tab.
2. Tap `Start`.
3. Confirm status changes to `Monitoring locally` or service readiness text.
4. Tap `Pause`.
5. Confirm monitoring stops and a stop event is recorded.

Expected result: camera/audio/motion services transition through the view model and local events are saved.

### 3. Manual Critical Alert
1. Open the Monitor tab.
2. Tap `Test`.
3. Confirm status changes to `Critical alert escalated`.
4. Open the Events tab.
5. Confirm `Manual test alert` appears.

Expected result: alert rules, push path, watch escalation path, home automation hook, event store, and event timeline are exercised.

### 4. Rules Configuration
1. Open the Rules tab.
2. Adjust noise threshold, stillness threshold, low humidity, and high humidity sliders.
3. Toggle low-light attention alerts.
4. Return to Monitor and start monitoring.

Expected result: rule configuration remains responsive and drives later alert evaluation.

### 5. Local Database Persistence
1. Start monitoring.
2. Trigger a manual alert.
3. Navigate to Events.
4. Confirm events are ordered newest first.
5. Relaunch without `--ui-testing` to verify SwiftData-backed persistence.

Expected result: production mode stores events locally on device; UI-test mode uses an isolated in-memory store.

### 6. APNs Backend Payload Verification
1. Run backend tests from `apns_provider`.
2. Confirm critical alerts use priority `10` and interruption level `critical`.
3. Confirm warning alerts use priority `5` and interruption level `time-sensitive`.

Expected result: backend produces APNs-ready payloads without requiring a live Apple push request during tests.

### 7. ML Model Pipeline
1. Run `bash ml/run_model_pipeline.sh`.
2. With no complete dataset, confirm a baseline `CryDetector.mlmodel` is generated.
3. With data in `data/cry`, `data/coo`, `data/noise`, and `data/silence`, confirm training replaces the baseline model.
4. Confirm `ml/validate_model.py` validates the exported model.

Expected result: the app always has a compile-ready Core ML model resource.

## Release Gate

Before production release:
1. `xcodebuild build-for-testing` must pass.
2. Unit tests must pass on a healthy simulator runner.
3. UI tests must pass from manual workflow dispatch with `run_ui_tests=true`.
4. Backend APNs payload tests must pass.
5. ML model validation must pass.
6. Manual QA scenarios above must be signed off on at least one iPhone and one iPad viewport.

# BabyMont Operational Manual

## Purpose

BabyMont is a local-first iOS baby monitoring app for nursery supervision. It coordinates live camera preview, audio classification, motion monitoring, humidity/location signals, alert rules, local event storage, CloudKit sync readiness, APNs-ready notification infrastructure, Apple Watch escalation hooks, and HomeKit readiness from a SwiftUI tab interface.

BabyMont is a support tool. It must not replace direct adult supervision, safe-sleep practice, emergency care, or professional medical advice.

## Operating Principles

- Keep monitoring local first. Camera, audio, motion, rule evaluation, and event storage run on device before any cloud dependency is used.
- Use the Monitor scene for live care decisions.
- Use the Backend scene for service control, readiness, APNs, CloudKit, location checkpoints, and test alerts.
- Use the Events scene as the operator audit trail.
- Use the Rules scene to tune alert sensitivity.
- Use Settings for operator preferences and high-level system status.

## App Navigation

BabyMont has five primary tabs.

| Tab | Primary role | Operator use |
| --- | --- | --- |
| Monitor | Live nursery view and current signal state | Start/pause monitoring, view camera, capture snapshots, inspect current audio/motion/humidity/alert signals |
| Events | Local event history | Review monitoring starts/stops, snapshots, alerts, location checkpoints, and sensor events |
| Rules | Alert configuration | Adjust noise, stillness, humidity, and low-light alert behavior |
| Backend | Service control center | Prepare notifications, sync CloudKit, capture location checkpoints, run test alerts, inspect APNs/CloudKit/Watch/HomeKit/date-time/location readiness |
| Settings | Preferences and status | Review thresholds, low-light preference, cloud status, and location status |

## First-Time Setup

1. Install BabyMont on the iPhone from Xcode or TestFlight.
2. Open the app and allow required permissions when prompted:
   - Camera for live preview and snapshots.
   - Microphone for audio classification.
   - Notifications for local alerts and APNs readiness.
   - Location for nursery location checkpoints.
3. Open the Backend tab.
4. Tap `Prepare`.
5. Confirm CloudKit readiness changes to `CloudKit ready` or a clear unavailable status.
6. Check Backend tiles for APNs, CloudKit, Watch, HomeKit, Date & Time, and Location.

## Daily Monitoring Workflow

1. Place the iPhone in a stable nursery position with a clear camera view.
2. Open the Monitor tab.
3. Tap `Start`.
4. Confirm the status changes to `Monitoring locally`.
5. Confirm the Live Stream area is visible.
6. Review signal cards:
   - Camera occupancy confidence and frame rate.
   - Audio classification and confidence.
   - Motion score and sustained stillness.
   - Humidity percentage when a sensor signal is available.
   - Active alert count.
7. Tap `Snapshot` when a local visual record is needed.
8. Open Events to confirm the snapshot or alert was stored.
9. Tap `Pause` when monitoring should stop.

## Monitor Tab Behavior

The Monitor tab is intentionally minimal and focused on care-state feedback.

- `Start` starts camera, audio, motion, and Apple location services.
- `Pause` stops local services, clears active alert candidates, resets rule cooldowns, and records a stop event.
- `Snapshot` captures a local image when a camera frame is available.
- The Local Event Store section shows recent events directly from the app event store.
- If no camera frame is available, the app reports `No camera frame available for snapshot`.

Expected healthy states:

- Status: `Monitoring locally` after Start.
- Camera: active frame rate and occupancy confidence when available.
- Audio: classification such as Ambient, Crying, Sustained Noise, or Silence.
- Motion: activity score plus sustained stillness seconds.
- Alerts: zero in normal conditions, nonzero when rules match.

## Backend Tab Behavior

The Backend tab is the service control center.

Operational buttons:

| Button | Function | Expected result |
| --- | --- | --- |
| Prepare | Requests notification authorization, registers for remote notifications, updates CloudKit with the APNs token, and refreshes cloud events | Cloud status updates to `CloudKit ready`, `CloudKit synced ... events`, or `CloudKit unavailable` |
| Sync | Fetches recent CloudKit events | Cloud event count and cloud status refresh |
| Locate | Starts location service and records a location checkpoint event | Events shows `Location checkpoint`; Backend shows location summary/detail |
| Snapshot | Captures a camera snapshot through the backend operations scene | Events shows `Snapshot captured` if a frame exists |
| Critical | Sends a manual critical test alert through push, Watch, HomeKit, local store, and CloudKit hooks | Events shows `Manual test alert` |
| Audio | Simulates a crying audio signal through the rule engine | Monitor shows `Attention alert recorded`; Events shows `Baby crying detected` |
| Motion | Simulates low movement/stillness through the rule engine | Monitor shows `Critical alert escalated`; Events shows `Prolonged low movement` |
| Humidity | Simulates high humidity through the rule engine | Monitor shows `Critical alert escalated`; Events shows `Nursery humidity high` |

Backend readiness tiles:

- APNs: notification authorization and token status.
- CloudKit: sync availability and latest cloud status.
- Watch: Apple Watch escalation state.
- HomeKit: nursery automation readiness.
- Date & Time: Apple device clock timestamp.
- Location: Apple location state, coordinate/locality, and accuracy detail.

## Events Tab Behavior

Events is the local audit trail. It should be checked after every critical operation.

Common event titles:

- `Monitoring started`
- `Monitoring stopped`
- `Snapshot captured`
- `Manual test alert`
- `Baby crying detected`
- `Prolonged low movement`
- `Nursery humidity high`
- `Location checkpoint`

Events are stored locally first. Cloud sync is optional and reported through Backend and Settings status.

## Rules Tab Operation

Rules tune alert sensitivity.

| Control | Meaning | Operational guidance |
| --- | --- | --- |
| Noise threshold | Sound confidence/level required before attention alerts | Raise it in noisy homes; lower it when the device is far from the crib |
| Stillness threshold | Motion score below which stillness can become concerning | Tune cautiously; avoid false positives from normal sleep |
| Low humidity | Lower acceptable humidity bound | Use nursery climate guidance and sensor quality checks |
| High humidity | Upper acceptable humidity bound | Use with real humidity sensor data when available |
| Low light attention alerts | Whether low light contributes to attention alerts | Enable when camera visibility is important overnight |

After changing rules, run the Backend test buttons for Audio, Motion, and Humidity, then verify results in Monitor and Events.

## Alert Severity Behavior

BabyMont uses rule-driven severity.

- Info: normal status events, monitoring start/stop, snapshots, and location checkpoints.
- Warning: crying, sustained noise before critical escalation, missing face/occupancy, and temperature/humidity concerns.
- Critical: sustained distress conditions, prolonged low movement, high-risk environmental states, and manual critical test alerts.

The rule engine suppresses duplicate alerts within cooldown windows so operators are not flooded by repeated events.

## Notifications, APNs, And Watch Escalation

Local alerts are generated on device for warning and critical events. The push service also exposes APNs-ready payloads for remote alert infrastructure.

Operational checks:

1. Open Backend.
2. Tap `Prepare`.
3. Confirm notification readiness and CloudKit status are visible.
4. Tap `Critical`.
5. Confirm the manual alert appears in Events.
6. Confirm Watch status is visible in Backend.

Supported notification actions in the app architecture:

- Acknowledge.
- Call partner.
- Open live stream.

Critical alerts should be used carefully and tested before production deployment.

## Camera And Snapshot Operation

The camera service uses AVFoundation for live preview and frame capture. Frames are exposed for Vision analysis, including occupancy confidence derived from face/person signals.

Operator checks:

1. Open Monitor.
2. Tap `Start`.
3. Confirm Live Stream is visible.
4. Confirm Camera signal shows an occupancy percentage.
5. Tap `Snapshot`.
6. Confirm `Snapshot captured`.
7. Open Events and verify the snapshot event.

If snapshot capture fails, check camera permission, camera availability, device lock state, and whether monitoring has started.

## Audio Operation

The audio service uses AVAudioEngine and SoundAnalysis-compatible classification pathways. It classifies crying, sustained noise, silence, and ambient sound.

Operator checks:

1. Open Backend.
2. Tap `Audio`.
3. Open Monitor.
4. Confirm `Attention alert recorded`.
5. Confirm Audio signal shows `Crying`.
6. Open Events and verify `Baby crying detected`.

For real-world use, confirm microphone permission and avoid placing the phone near fans, televisions, or constant mechanical noise.

## Motion And Humidity Operation

Motion signals are monitored locally and evaluated against stillness rules. Humidity is represented as an environmental signal and can be connected to real sensor data through the service architecture.

Operator checks:

1. Open Backend.
2. Tap `Motion`.
3. Confirm Monitor reports `Critical alert escalated`.
4. Confirm Events shows `Prolonged low movement`.
5. Open Backend.
6. Tap `Humidity`.
7. Confirm Events shows `Nursery humidity high`.

Use environmental alerts as decision support. Always verify room conditions with reliable hardware.

## Location And Date-Time Tracking

Location checkpoints use Apple location services and the device clock.

Operator checks:

1. Open Backend.
2. Confirm Date & Time tile is visible.
3. Confirm Location tile is visible.
4. Tap `Locate`.
5. Open Events.
6. Confirm `Location checkpoint`.
7. Return to Backend and check location status details.

Location accuracy depends on device permissions, signal quality, and iOS location availability.

## CloudKit And Local-First Storage

BabyMont stores events locally first. CloudKit is used as an optional sync layer for care-team history and remote continuity.

Expected behavior:

- If CloudKit is available, Backend and Settings show ready/synced/saved status.
- If CloudKit is unavailable, local monitoring and event storage continue.
- Operators should not depend on cloud sync for immediate safety response.

## Troubleshooting

| Symptom | Likely cause | Action |
| --- | --- | --- |
| Camera unavailable | Camera permission denied, camera in use, or device locked | Grant permission, close other camera apps, unlock device, restart monitoring |
| No snapshot | No latest camera frame | Start monitoring and wait for preview before tapping Snapshot |
| No audio alert | Microphone permission or threshold issue | Grant microphone permission, check noise threshold, run Backend Audio test |
| Duplicate alerts do not appear | Cooldown suppression is active | Wait for cooldown or reset by pausing and restarting monitoring |
| CloudKit unavailable | iCloud entitlement/account/network unavailable | Continue local monitoring; check Apple ID, network, entitlements, and Backend Sync |
| Watch not paired | No paired/reachable Apple Watch | Continue iPhone alerts; pair Watch before relying on escalation |
| HomeKit unavailable | Home app or room not configured | Configure HomeKit and nursery room; treat HomeKit as optional |
| Location missing | Location permission unavailable or weak signal | Grant permission, improve signal, tap Locate again |

## Production Readiness Checklist

Before live use:

- Physical iPhone build installs successfully.
- Monitor Start/Pause works.
- Live Stream is visible.
- Snapshot creates an Events entry.
- Backend Prepare updates notification/cloud status.
- Backend Sync updates cloud event count.
- Backend Critical, Audio, Motion, and Humidity tests create Events entries.
- Rules controls are tuned for the nursery environment.
- Location checkpoint creates an Events entry.
- Notifications are allowed in iOS Settings.
- Apple Watch and HomeKit are configured if used.
- Caregivers understand BabyMont is an aid, not a replacement for supervision.

## Verified Test Coverage

The latest physical-device verification ran on Christopher's iPhone and passed:

- 16 UI and launch tests.
- 22 unit and architecture tests.
- Monitor, Events, Rules, Backend, and Settings navigation.
- Start/pause monitoring.
- Audio, motion, humidity, manual critical alert, snapshot, and location checkpoint flows.
- Event storage and service integration across view model, rule engine, push, Watch, HomeKit, CloudKit, and local store.


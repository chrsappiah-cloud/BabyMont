# BabyMont App Store / TestFlight Preparation

## App Listing Copy

**Name:** BabyMont

**Subtitle:** Local-first baby monitoring

**Promotional Text:** BabyMont combines live camera preview, real-time audio intelligence, motion and nursery environment signals into a calm care dashboard built for fast local alerts and optional Apple ecosystem escalation.

**Short Description:** A private, local-first iOS baby monitor with live camera preview, crying/noise analysis, motion and humidity alert rules, local event storage, CloudKit-ready sync and Apple Watch escalation.

**Keywords:** baby monitor, nursery, crying detection, local alerts, Apple Watch, CloudKit, camera, audio, motion, humidity, parent care

## Review Notes

BabyMont is designed as a local-first monitoring assistant. Camera and microphone access are used only for nursery monitoring and on-device signal analysis. Location access is used for optional caregiver location checkpoints. CloudKit, APNs and Apple Watch escalation are optional support paths for family/care-team coordination.

## Screenshot Pack

- `AppStoreAssets/screenshots/iphone-6-9/`: 5 portrait screenshots at 1320 x 2868.
- `AppStoreAssets/screenshots/ipad-13/`: 3 portrait screenshots at 2048 x 2732.
- `AppStoreAssets/promotional/`: social/promotional hero images and generated source art.

## TestFlight Build Checklist

1. Confirm bundle identifier `wcs.BabyMont` exists in Apple Developer and App Store Connect.
2. Enable Push Notifications and iCloud/CloudKit capabilities for the App ID.
3. Replace local archive development signing with App Store Connect distribution signing.
4. Archive with Release configuration and destination `generic/platform=iOS`.
5. Export with `TestFlightExportOptions.plist` or upload directly from Xcode Organizer.
6. Complete App Privacy details for camera, microphone, location, identifiers/events stored locally and optional iCloud sync.
7. Add beta test information explaining nursery monitoring, alert actions, and Apple Watch/APNs escalation.
8. Upload the iPhone and iPad screenshot sets from `AppStoreAssets`.

## Validated Locally

- Release archive succeeded for generic iOS.
- Current local archive was signed with Apple Development, so it is a technical archive validation rather than a final TestFlight upload artifact.
- Existing physical-device E2E suite previously passed on Christopher's iPhone for monitoring, camera snapshot, audio alert, motion alert, humidity alert, backend actions, navigation tabs, CloudKit readiness and location checkpoint behavior.

# BabyMont Sound Models

Place `CryDetector.mlmodel` in this folder. Xcode compiles it into `CryDetector.mlmodelc` at build time, which `LocalAudioMonitoringService` loads from the app bundle.

The training pipeline in `/Applications/BabyMont/ml` exports the model here and writes `CryDetector.preprocessing.json` with the audio preprocessing settings used during training.

Before real labeled audio exists, run `python ml/create_dummy_cry_model.py` to generate a development baseline model with the same Core ML input/output schema. It is suitable for app integration testing, alerts, notifications, and watch escalation, but it is not a clinically or commercially valid baby-cry model.

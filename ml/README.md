# CryDetector Model Pipeline

BabyMont can build `CryDetector.mlmodel` in GitHub Actions or locally through Docker.

## Local Docker

Build the image from the repo root:

```bash
docker build -t babymont-cry-model .
```

Generate a baseline model, or train with real data when all class folders contain clips:

```bash
docker run --rm -v "$(pwd):/workspace" babymont-cry-model
```

The model is written to:

```text
BabyMont/Resources/Models/CryDetector.mlmodel
```

Xcode compiles that file into `CryDetector.mlmodelc` at build time. The app loads `CryDetector.mlmodelc` from the bundle.

## Dataset

Use short mono audio clips under:

```text
data/cry/
data/coo/
data/noise/
data/silence/
```

The Docker and CI jobs generate a synthetic baseline model when any class is missing data. Once all four classes contain clips, they run `ml/train_cry_model.py`.

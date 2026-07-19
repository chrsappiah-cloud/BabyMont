from __future__ import annotations

import argparse
import platform
from pathlib import Path

import coremltools as ct
import librosa
import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MODEL_PATH = REPO_ROOT / "BabyMont" / "Resources" / "Models" / "CryDetector.mlmodel"
DATA_ROOT = REPO_ROOT / "data"

CLASSES = ["cry", "coo", "noise", "silence"]
SAMPLE_RATE = 16_000
DURATION_SECONDS = 2.0
N_SAMPLES = int(SAMPLE_RATE * DURATION_SECONDS)
N_MELS = 96
N_FFT = 2048
HOP_LENGTH = 512


def first_clip() -> Path:
    for class_name in CLASSES:
        class_dir = DATA_ROOT / class_name
        for pattern in ("*.wav", "*.m4a", "*.mp3", "*.flac", "*.aif", "*.aiff"):
            match = next(iter(sorted(class_dir.glob(pattern))), None)
            if match is not None:
                return match
    raise SystemExit(f"No validation clips found under {DATA_ROOT}.")


def preprocess(path: Path) -> np.ndarray:
    audio, _ = librosa.load(path, sr=SAMPLE_RATE, mono=True)
    if len(audio) < N_SAMPLES:
        audio = np.pad(audio, (0, N_SAMPLES - len(audio)))
    else:
        audio = audio[:N_SAMPLES]

    spectrogram = librosa.feature.melspectrogram(
        y=audio,
        sr=SAMPLE_RATE,
        n_fft=N_FFT,
        hop_length=HOP_LENGTH,
        n_mels=N_MELS,
    )
    mel = librosa.power_to_db(spectrogram, ref=np.max).astype(np.float32)
    mel = (mel - mel.mean()) / (mel.std() + 1e-6)
    return mel.T[np.newaxis, ..., np.newaxis].astype(np.float32)


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate CryDetector.mlmodel on one audio clip.")
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL_PATH)
    parser.add_argument("--audio", type=Path, default=None)
    args = parser.parse_args()

    if not args.model.exists():
        raise SystemExit(f"Model does not exist: {args.model}")

    model = ct.models.MLModel(str(args.model))

    if platform.system() != "Darwin":
        spec = model.get_spec()
        input_names = [item.name for item in spec.description.input]
        output_names = [item.name for item in spec.description.output]
        print(f"Validated Core ML spec on {platform.system()}.")
        print(f"Inputs: {input_names}")
        print(f"Outputs: {output_names}")
        if "input" not in input_names:
            raise SystemExit("Model is missing required input named 'input'.")
        if "classLabel" not in output_names:
            raise SystemExit("Model is missing required output named 'classLabel'.")
        return

    clip = args.audio or first_clip()
    prediction = model.predict({"input": preprocess(clip)})
    print(f"Validated clip: {clip}")
    print(f"Predicted class: {prediction.get('classLabel')}")
    print(f"Probabilities: {prediction.get('classProbability')}")


if __name__ == "__main__":
    main()

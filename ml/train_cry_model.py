from __future__ import annotations

import argparse
import json
from pathlib import Path

import coremltools as ct
import librosa
import numpy as np
import tensorflow as tf
from tensorflow.keras import layers, models


REPO_ROOT = Path(__file__).resolve().parents[1]
DATA_ROOT = REPO_ROOT / "data"
DEFAULT_OUTPUT = REPO_ROOT / "BabyMont" / "Resources" / "Models" / "CryDetector.mlmodel"
METADATA_OUTPUT = REPO_ROOT / "BabyMont" / "Resources" / "Models" / "CryDetector.preprocessing.json"

CLASSES = ["cry", "coo", "noise", "silence"]
SAMPLE_RATE = 16_000
DURATION_SECONDS = 2.0
N_SAMPLES = int(SAMPLE_RATE * DURATION_SECONDS)
N_MELS = 96
N_FFT = 2048
HOP_LENGTH = 512
SEED = 42


def audio_files_for_class(class_name: str) -> list[Path]:
    class_dir = DATA_ROOT / class_name
    return sorted(
        path
        for pattern in ("*.wav", "*.m4a", "*.mp3", "*.flac", "*.aif", "*.aiff")
        for path in class_dir.glob(pattern)
    )


def load_audio(path: Path) -> np.ndarray:
    audio, _ = librosa.load(path, sr=SAMPLE_RATE, mono=True)
    if len(audio) < N_SAMPLES:
        audio = np.pad(audio, (0, N_SAMPLES - len(audio)))
    else:
        audio = audio[:N_SAMPLES]
    return audio.astype(np.float32)


def audio_to_mel(audio: np.ndarray) -> np.ndarray:
    spectrogram = librosa.feature.melspectrogram(
        y=audio,
        sr=SAMPLE_RATE,
        n_fft=N_FFT,
        hop_length=HOP_LENGTH,
        n_mels=N_MELS,
    )
    log_spectrogram = librosa.power_to_db(spectrogram, ref=np.max)
    return log_spectrogram.astype(np.float32)


def normalize(mel: np.ndarray) -> np.ndarray:
    return (mel - mel.mean()) / (mel.std() + 1e-6)


def build_dataset() -> tuple[np.ndarray, np.ndarray]:
    features: list[np.ndarray] = []
    labels: list[int] = []
    class_counts: dict[str, int] = {}

    for label_index, class_name in enumerate(CLASSES):
        files = audio_files_for_class(class_name)
        class_counts[class_name] = len(files)
        for path in files:
            audio = load_audio(path)
            mel = normalize(audio_to_mel(audio))
            features.append(mel.T)
            labels.append(label_index)

    missing = [name for name, count in class_counts.items() if count == 0]
    if missing:
        raise SystemExit(
            "Missing training audio for classes: "
            + ", ".join(missing)
            + f". Add clips under {DATA_ROOT}/<class>/ before training."
        )
    if len(features) < len(CLASSES) * 2:
        raise SystemExit("Training needs at least two clips per class for a validation split.")

    x = np.stack(features, axis=0).astype(np.float32)[..., np.newaxis]
    y = np.asarray(labels, dtype=np.int32)
    return x, y


def build_model(input_shape: tuple[int, int, int], num_classes: int) -> tf.keras.Model:
    inputs = layers.Input(shape=input_shape, name="input")
    x = layers.Conv2D(32, (3, 3), activation="relu", padding="same")(inputs)
    x = layers.BatchNormalization()(x)
    x = layers.MaxPooling2D((2, 2))(x)
    x = layers.Conv2D(64, (3, 3), activation="relu", padding="same")(x)
    x = layers.BatchNormalization()(x)
    x = layers.MaxPooling2D((2, 2))(x)
    x = layers.Conv2D(128, (3, 3), activation="relu", padding="same")(x)
    x = layers.BatchNormalization()(x)
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.Dense(64, activation="relu")(x)
    x = layers.Dropout(0.5)(x)
    outputs = layers.Dense(num_classes, activation="softmax", name="classProbability")(x)
    return models.Model(inputs, outputs, name="CryDetector")


def split_dataset(x: np.ndarray, y: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    rng = np.random.default_rng(SEED)
    train_indices: list[int] = []
    validation_indices: list[int] = []

    for label in range(len(CLASSES)):
        indices = np.where(y == label)[0]
        rng.shuffle(indices)
        split = max(1, int(0.8 * len(indices)))
        if split >= len(indices):
            split = len(indices) - 1
        train_indices.extend(indices[:split])
        validation_indices.extend(indices[split:])

    rng.shuffle(train_indices)
    rng.shuffle(validation_indices)
    return x[train_indices], y[train_indices], x[validation_indices], y[validation_indices]


def convert_to_core_ml(model: tf.keras.Model, sample_shape: tuple[int, ...], output_path: Path) -> None:
    classifier_config = ct.ClassifierConfig(
        class_labels=CLASSES,
        predicted_feature_name="classLabel",
        predicted_probabilities_output="classProbability",
    )
    mlmodel = ct.convert(
        model,
        inputs=[ct.TensorType(name="input", shape=sample_shape, dtype=np.float32)],
        classifier_config=classifier_config,
        minimum_deployment_target=ct.target.iOS17,
    )
    mlmodel.short_description = "BabyMont cry, coo, noise, and silence classifier."
    mlmodel.input_description["input"] = "Normalized log-mel spectrogram with shape [1, time, mel, 1]."
    mlmodel.output_description["classLabel"] = "Predicted nursery sound class."
    mlmodel.output_description["classProbability"] = "Per-class confidence scores."
    output_path.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(output_path)


def write_metadata(output_path: Path, x_shape: tuple[int, ...]) -> None:
    metadata = {
        "model": str(output_path.relative_to(REPO_ROOT)),
        "classes": CLASSES,
        "sampleRate": SAMPLE_RATE,
        "durationSeconds": DURATION_SECONDS,
        "nSamples": N_SAMPLES,
        "nMels": N_MELS,
        "nFFT": N_FFT,
        "hopLength": HOP_LENGTH,
        "inputShape": list(x_shape),
    }
    METADATA_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    METADATA_OUTPUT.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Train and export BabyMont CryDetector.mlmodel.")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--epochs", type=int, default=20)
    parser.add_argument("--batch-size", type=int, default=32)
    args = parser.parse_args()

    tf.keras.utils.set_random_seed(SEED)
    x, y = build_dataset()
    x_train, y_train, x_validation, y_validation = split_dataset(x, y)

    model = build_model(x.shape[1:], len(CLASSES))
    model.compile(
        optimizer="adam",
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    model.summary()
    model.fit(
        x_train,
        y_train,
        validation_data=(x_validation, y_validation),
        epochs=args.epochs,
        batch_size=args.batch_size,
    )

    validation_loss, validation_accuracy = model.evaluate(x_validation, y_validation, verbose=0)
    print(f"Validation loss: {validation_loss:.4f}")
    print(f"Validation accuracy: {validation_accuracy:.4f}")

    convert_to_core_ml(model, (1, *x.shape[1:]), args.output)
    write_metadata(args.output, (1, *x.shape[1:]))
    print(f"Saved Core ML model to {args.output}")


if __name__ == "__main__":
    main()

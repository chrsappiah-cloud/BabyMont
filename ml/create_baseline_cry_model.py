from __future__ import annotations

import argparse
import json
from pathlib import Path

import coremltools as ct
import numpy as np
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers, models


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = REPO_ROOT / "BabyMont" / "Resources" / "Models" / "CryDetector.mlmodel"
METADATA_OUTPUT = REPO_ROOT / "BabyMont" / "Resources" / "Models" / "CryDetector.preprocessing.json"

TIME_STEPS = 63
N_MELS = 96
NUM_CLASSES = 4
CLASSES = ["cry", "coo", "noise", "silence"]
SEED = 42


def build_model(input_shape: tuple[int, int, int]) -> tf.keras.Model:
    inputs = layers.Input(shape=input_shape, name="input")
    x = layers.Conv2D(16, (3, 3), activation="relu", padding="same")(inputs)
    x = layers.MaxPooling2D((2, 2))(x)
    x = layers.Conv2D(32, (3, 3), activation="relu", padding="same")(x)
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.Dense(16, activation="relu")(x)
    outputs = layers.Dense(NUM_CLASSES, activation="softmax", name="classProbability")(x)
    return models.Model(inputs, outputs, name="CryDetectorBaseline")


def synthetic_dataset(sample_count: int) -> tuple[np.ndarray, np.ndarray]:
    rng = np.random.default_rng(SEED)
    x = rng.normal(0, 0.25, size=(sample_count, TIME_STEPS, N_MELS, 1)).astype(np.float32)
    y = np.arange(sample_count, dtype=np.int32) % NUM_CLASSES

    for index, label in enumerate(y):
        if CLASSES[label] == "cry":
            x[index, 12:42, 18:70, 0] += 1.20
            x[index, 22:50, 60:82, 0] += 0.60
        elif CLASSES[label] == "coo":
            x[index, 15:52, 28:48, 0] += 0.55
        elif CLASSES[label] == "noise":
            x[index, :, :, 0] += rng.normal(0, 0.55, size=(TIME_STEPS, N_MELS))
        elif CLASSES[label] == "silence":
            x[index, :, :, 0] *= 0.08

    return x, keras.utils.to_categorical(y, NUM_CLASSES)


def convert(model: tf.keras.Model, output_path: Path) -> None:
    classifier_config = ct.ClassifierConfig(
        class_labels=CLASSES,
        predicted_feature_name="classLabel",
        predicted_probabilities_output="classProbability",
    )
    mlmodel = ct.convert(
        model,
        inputs=[ct.TensorType(name="input", shape=(1, TIME_STEPS, N_MELS, 1), dtype=np.float32)],
        classifier_config=classifier_config,
        minimum_deployment_target=ct.target.iOS17,
    )
    mlmodel.short_description = "Baseline BabyMont cry classifier for development before real audio training."
    mlmodel.input_description["input"] = "Normalized log-mel spectrogram with shape [1, time, mel, 1]."
    mlmodel.output_description["classLabel"] = "Predicted class: cry, coo, noise, or silence."
    mlmodel.output_description["classProbability"] = "Per-class confidence scores."
    output_path.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(output_path)


def write_metadata(output_path: Path) -> None:
    metadata = {
        "model": str(output_path.relative_to(REPO_ROOT)),
        "kind": "synthetic-baseline",
        "classes": CLASSES,
        "sampleRate": 16_000,
        "durationSeconds": 2.0,
        "nMels": N_MELS,
        "nFFT": 2048,
        "hopLength": 512,
        "inputShape": [1, TIME_STEPS, N_MELS, 1],
        "warning": "Development baseline only. Replace with a model trained on real labeled nursery audio.",
    }
    METADATA_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    METADATA_OUTPUT.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Create a baseline CryDetector.mlmodel without real audio data.")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--epochs", type=int, default=3)
    parser.add_argument("--samples", type=int, default=128)
    args = parser.parse_args()

    tf.keras.utils.set_random_seed(SEED)
    x, y = synthetic_dataset(args.samples)
    model = build_model((TIME_STEPS, N_MELS, 1))
    model.compile(optimizer="adam", loss="categorical_crossentropy", metrics=["accuracy"])
    model.fit(x, y, epochs=args.epochs, batch_size=16, verbose=1)
    convert(model, args.output)
    write_metadata(args.output)
    print(f"Saved baseline Core ML model to {args.output}")


if __name__ == "__main__":
    main()

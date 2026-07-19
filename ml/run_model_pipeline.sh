#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p BabyMont/Resources/Models

has_class_data() {
  find "data/$1" -type f ! -name ".gitkeep" 2>/dev/null | grep -q .
}

if has_class_data cry && has_class_data coo && has_class_data noise && has_class_data silence; then
  python ml/train_cry_model.py
else
  echo "No complete audio dataset found; generating baseline CryDetector.mlmodel."
  python ml/create_dummy_cry_model.py
fi

python ml/validate_model.py --model BabyMont/Resources/Models/CryDetector.mlmodel

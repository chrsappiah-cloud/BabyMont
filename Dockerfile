FROM python:3.11-slim

WORKDIR /workspace

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

COPY ml/requirements.txt ./ml/requirements.txt

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r ml/requirements.txt

COPY ml/ ./ml/
COPY data/ ./data/
RUN mkdir -p ./BabyMont/Resources/Models

CMD ["bash", "/workspace/ml/run_model_pipeline.sh"]

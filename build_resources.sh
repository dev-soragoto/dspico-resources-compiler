#!/bin/sh
set -eu

IMAGE_NAME=${IMAGE_NAME:-dspico-compiler:latest}
INPUT_DIR=${1:-$(pwd)/inputs}
OUTPUT_DIR=${2:-$(pwd)/outputs}

echo "Building Docker image $IMAGE_NAME..."
docker build -t "$IMAGE_NAME" .

echo "Running container (inputs: $INPUT_DIR -> /inputs read-only, outputs: $OUTPUT_DIR -> /outputs)..."
mkdir -p "$OUTPUT_DIR"
docker run --rm \
  -v "$INPUT_DIR":/inputs:ro \
  -v "$OUTPUT_DIR":/outputs \
  "$IMAGE_NAME"

echo "Finished. Outputs are in $OUTPUT_DIR"

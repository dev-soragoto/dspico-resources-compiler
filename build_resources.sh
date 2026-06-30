#!/bin/sh
set -eu

IMAGE_NAME=${IMAGE_NAME:-dspico-compiler:latest}
INPUT_DIR=${1:-$(pwd)/inputs}
OUTPUT_DIR=${2:-$(pwd)/outputs}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DSPICO_BOOTLOADER_REPO=${DSPICO_BOOTLOADER_REPO:-https://github.com/LNH-team/dspico-bootloader.git}
DSPICO_BOOTLOADER_REF=${DSPICO_BOOTLOADER_REF:-develop}
DSROMENCRYPTOR_REPO=${DSROMENCRYPTOR_REPO:-https://github.com/Gericom/DSRomEncryptor.git}
DSROMENCRYPTOR_REF=${DSROMENCRYPTOR_REF:-HEAD}
DSPICO_WRFUXXED_REPO=${DSPICO_WRFUXXED_REPO:-https://github.com/LNH-team/dspico-wrfuxxed.git}
DSPICO_WRFUXXED_REF=${DSPICO_WRFUXXED_REF:-develop}
DSPICO_FIRMWARE_REPO=${DSPICO_FIRMWARE_REPO:-https://github.com/LNH-team/dspico-firmware.git}
DSPICO_FIRMWARE_REF=${DSPICO_FIRMWARE_REF:-develop}
DSPICO_FIRMWARE_EXTRA_REFS=${DSPICO_FIRMWARE_EXTRA_REFS:-}
FIRM_TO_NDS_REPO=${FIRM_TO_NDS_REPO:-https://github.com/amt911/firm-to-nds.git}
FIRM_TO_NDS_REF=${FIRM_TO_NDS_REF:-HEAD}

echo "Building Docker image $IMAGE_NAME..."
docker build -t "$IMAGE_NAME" .

echo "Running container (inputs: $INPUT_DIR, outputs: $OUTPUT_DIR)..."
mkdir -p "$OUTPUT_DIR"
docker run --rm \
  -v "$INPUT_DIR":/inputs:ro \
  -v "$OUTPUT_DIR":/outputs \
  -v "$SCRIPT_DIR/compile_resources.sh":/dspico/compile_resources.sh:ro \
  -e ENABLE_WRFUXXED="${ENABLE_WRFUXXED:-0}" \
  -e ENABLE_NTRBOOT="${ENABLE_NTRBOOT:-0}" \
  -e DSPICO_BOOTLOADER_REPO="$DSPICO_BOOTLOADER_REPO" \
  -e DSPICO_BOOTLOADER_REF="$DSPICO_BOOTLOADER_REF" \
  -e DSROMENCRYPTOR_REPO="$DSROMENCRYPTOR_REPO" \
  -e DSROMENCRYPTOR_REF="$DSROMENCRYPTOR_REF" \
  -e DSPICO_WRFUXXED_REPO="$DSPICO_WRFUXXED_REPO" \
  -e DSPICO_WRFUXXED_REF="$DSPICO_WRFUXXED_REF" \
  -e DSPICO_FIRMWARE_REPO="$DSPICO_FIRMWARE_REPO" \
  -e DSPICO_FIRMWARE_REF="$DSPICO_FIRMWARE_REF" \
  -e DSPICO_FIRMWARE_EXTRA_REFS="$DSPICO_FIRMWARE_EXTRA_REFS" \
  -e FIRM_TO_NDS_REPO="$FIRM_TO_NDS_REPO" \
  -e FIRM_TO_NDS_REF="$FIRM_TO_NDS_REF" \
  --entrypoint bash \
  "$IMAGE_NAME" -lc '/dspico/compile_resources.sh'

echo "Finished. Outputs are in $OUTPUT_DIR"

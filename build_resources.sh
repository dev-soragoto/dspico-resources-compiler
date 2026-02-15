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
  --entrypoint bash \
  "$IMAGE_NAME" -lc '
set -eux
# If inputs are required by your build, they are mounted at /inputs (ro)
TMPDIR=/tmp/dspico-dldi
rm -rf "$TMPDIR"
git clone https://github.com/LNH-team/dspico-dldi.git "$TMPDIR"
cd "$TMPDIR"
# Load wonderful environment if available
[ -f /opt/wonderful/bin/wf-env ] && . /opt/wonderful/bin/wf-env || true
# Try to build with male, fall back to make
if command -v male >/dev/null 2>&1; then
  echo "building with male"
  male
else
  echo "male not found, trying make"
  make -j$(nproc)
fi
# Copy likely artifacts to /outputs/dspico-dldi
mkdir -p /outputs/dspico-dldi
# Copy exact artifacts produced by the Makefile:
# - top-level *.dldi (e.g. DSpico.dldi)
# - build/<NAME>/*.dldi or build/<NAME>/<NAME>.dldi
cp -v ./*.dldi /outputs/dspico-dldi 2>/dev/null || true
cp -v build/*/*.dldi /outputs/dspico-dldi 2>/dev/null || true
cp -v build/*/*/*.dldi /outputs/dspico-dldi 2>/dev/null || true
cp -v build/* /outputs/dspico-dldi 2>/dev/null || true
# Also copy any generated binaries
cp -v bin/* /outputs/dspico-dldi 2>/dev/null || true
# Fallback: copy repo for debugging if nothing else found
if [ -z "$(ls -A /outputs/dspico-dldi 2>/dev/null || true)" ]; then
  cp -r . /outputs/dspico-dldi/src || true
fi
echo "Done. Artifacts (or repo) are in /outputs/dspico-dldi"
'

echo "Finished. Outputs are in $OUTPUT_DIR"

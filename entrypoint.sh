#!/bin/sh
set -eu

# Entry point for the dspico compiler container.
# - Ensures /inputs exists and is not empty (to force user to mount copyrighted files)
# - Sources the wonderful toolchain environment if present
# - Runs a compiler script/binary if found under /dspico/app

INPUT_DIR=${INPUT_DIR:-/inputs}
OUTPUT_DIR=${OUTPUT_DIR:-/outputs}

echo "[dspico-compiler] Input: $INPUT_DIR  Output: $OUTPUT_DIR"

if [ ! -d "$INPUT_DIR" ]; then
  echo "ERROR: Input directory $INPUT_DIR does not exist. Mount your inputs with -v /path/to/inputs:$INPUT_DIR"
  exit 2
fi

if [ -z "$(ls -A "$INPUT_DIR")" ]; then
  echo "ERROR: Input directory $INPUT_DIR is empty. Place the required files and retry."
  exit 3
fi

mkdir -p "$OUTPUT_DIR"

# Source wonderful environment if available so wf-* tools are on PATH
if [ -f /opt/wonderful/bin/wf-env ]; then
  echo "[dspico-compiler] Sourcing /opt/wonderful/bin/wf-env"
  # shellcheck disable=SC1091
  . /opt/wonderful/bin/wf-env
fi

# Prefer an executable shell wrapper if provided
if [ -x /dspico/app/compile_resources.sh ]; then
  echo "[dspico-compiler] Running /dspico/app/compile_resources.sh"
  exec /dspico/app/compile_resources.sh "$INPUT_DIR" "$OUTPUT_DIR"
fi

# Prefer python script if provided
if command -v python3 >/dev/null 2>&1 && [ -f /dspico/app/compile_resources.py ]; then
  echo "[dspico-compiler] Running python3 /dspico/app/compile_resources.py"
  exec python3 /dspico/app/compile_resources.py "$INPUT_DIR" "$OUTPUT_DIR"
fi

echo "[dspico-compiler] No compiler found in /dspico/app. Falling back to safe copier."
for f in "$INPUT_DIR"/*; do
  base=$(basename "$f")
  cp "$f" "$OUTPUT_DIR/${base}.res"
done

echo "[dspico-compiler] Done. Outputs are in $OUTPUT_DIR"

#!/usr/bin/env bash
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INPUT_DIR="${INPUT_DIR:-$ROOT_DIR/inputs}"
BOOT9STRAP_URL="${BOOT9STRAP_URL:-}"
GBARUNNER2_URL="${GBARUNNER2_URL:-}"

sha1_file() {
  sha1sum "$1" | awk '{print $1}'
}

github_api_curl() {
  local url="$1"
  local token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  if [ -n "$token" ]; then
    curl -fsL \
      -H "Authorization: Bearer $token" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$url"
  else
    curl -fsL \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$url"
  fi
}

download_file() {
  local url="$1" dest="$2" expected_sha1="${3:-}"
  mkdir -p "$(dirname "$dest")"
  if [ ! -f "$dest" ]; then
    curl -fL "$url" -o "$dest"
  fi
  if [ -n "$expected_sha1" ]; then
    local actual_sha1
    actual_sha1="$(sha1_file "$dest")"
    if [ "$actual_sha1" != "$expected_sha1" ]; then
      echo "ERROR: SHA1 mismatch for $dest" >&2
      echo "expected: $expected_sha1" >&2
      echo "actual:   $actual_sha1" >&2
      exit 1
    fi
  fi
}

extract_boot9strap_ntr() {
  local zip_file="$1" dest="$2"
  local firm_path
  firm_path="$(unzip -Z1 "$zip_file" | grep 'boot9strap_ntr\.firm$' | head -n 1)"
  [ -n "$firm_path" ] || {
    echo "ERROR: boot9strap_ntr.firm not found in $zip_file" >&2
    exit 1
  }
  unzip -p "$zip_file" "$firm_path" > "$dest"
}

extract_gba_bios() {
  local zip_file="$1" dest="$2"
  local bios_path
  bios_path="$(unzip -Z1 "$zip_file" | grep 'gba_bios\.bin$' | head -n 1)"
  [ -n "$bios_path" ] || {
    echo "ERROR: gba_bios.bin not found in $zip_file" >&2
    exit 1
  }
  unzip -p "$zip_file" "$bios_path" > "$dest"
}

latest_boot9strap_ntr_url() {
  github_api_curl "https://api.github.com/repos/SciresM/boot9strap/releases/latest" \
    | sed 's#\\/#/#g' \
    | tr ',' '\n' \
    | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | grep '/boot9strap-[^/]*-ntr\.zip$' \
    | grep -v 'devkit' \
    | head -n 1
}

latest_gbarunner2_url() {
  github_api_curl "https://api.github.com/repos/Gericom/GBARunner2/releases/latest" \
    | sed 's#\\/#/#g' \
    | tr ',' '\n' \
    | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | grep '/GBARunner2_arm9dldi_ds\.nds$' \
    | head -n 1
}

mkdir -p "$INPUT_DIR/blowfish" "$INPUT_DIR/wrfuxxed" "$INPUT_DIR/ntrboot" "$INPUT_DIR/bios"
mkdir -p "$INPUT_DIR/releases"

download_file \
  "https://archive.org/download/wrfu_0.60_fixed/wrfu.srl" \
  "$INPUT_DIR/wrfuxxed/dsimode.nds" \
  "2d65fb7a0c62a4f08954b98c95f42b804fccfd26"

download_file \
  "https://github.com/DS-Homebrew/nds-bootstrap/raw/342b9408f761c1f3f03aac154c9e0aab1707e10f/retail/nitrofiles/encr_data.bin" \
  "$INPUT_DIR/blowfish/ntrBlowfish.bin" \
  "84e467f2485078e401a17a5f231e3fe6e9686648"

download_file \
  "https://github.com/DS-Homebrew/nds-bootstrap/raw/342b9408f761c1f3f03aac154c9e0aab1707e10f/retail/nitrofiles/dsi_encr_data.bin" \
  "$INPUT_DIR/blowfish/twlBlowfish.bin" \
  "2dea11191f28c6cc1956dadb8941affd4b2b5102"

download_file \
  "https://wiki.ds-homebrew.com/assets/files/default.gcd" \
  "$INPUT_DIR/ntrboot/default.gcd" \
  "eca89918bbff09090a43e67f2805d9743e2ac343"

download_file \
  "https://archive.org/download/nds-bios-firmware/bios7.bin" \
  "$INPUT_DIR/bios/biosnds7.rom" \
  "24f67bdea115a2c847c8813a262502ee1607b7df"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
boot9strap_zip="$tmp_dir/boot9strap-ntr.zip"
gba_bios_zip="$tmp_dir/gba_bios.zip"
gbarunner2_nds="$tmp_dir/GBARunner2_arm9dldi_ds.nds"

download_file \
  "https://archive.org/download/gba_bios_202501/gba_bios.zip" \
  "$gba_bios_zip"
extract_gba_bios "$gba_bios_zip" "$INPUT_DIR/bios/bios.bin"
gba_bios_sha1="$(sha1_file "$INPUT_DIR/bios/bios.bin")"
if [ "$gba_bios_sha1" != "300c20df6731a33952ded8c436f7f186d25d3492" ]; then
  echo "ERROR: SHA1 mismatch for $INPUT_DIR/bios/bios.bin" >&2
  echo "expected: 300c20df6731a33952ded8c436f7f186d25d3492" >&2
  echo "actual:   $gba_bios_sha1" >&2
  exit 1
fi

if [ -z "$BOOT9STRAP_URL" ]; then
  BOOT9STRAP_URL="$(latest_boot9strap_ntr_url)"
fi
[ -n "$BOOT9STRAP_URL" ] || {
  echo "ERROR: Could not resolve latest boot9strap ntr zip URL" >&2
  exit 1
}
curl -fL "$BOOT9STRAP_URL" -o "$boot9strap_zip"
extract_boot9strap_ntr "$boot9strap_zip" "$INPUT_DIR/ntrboot/boot9strap_ntr.firm"

boot9strap_sha1="$(sha1_file "$INPUT_DIR/ntrboot/boot9strap_ntr.firm")"
echo "boot9strap_ntr.firm SHA1: $boot9strap_sha1"

download_file \
  "https://github.com/LNH-team/dspico-dldi/releases/latest/download/DSpico.dldi" \
  "$INPUT_DIR/releases/DSpico.dldi"

download_file \
  "https://github.com/LNH-team/pico-loader/releases/latest/download/Pico_Loader_DSPICO.zip" \
  "$INPUT_DIR/releases/Pico_Loader_DSPICO.zip"

download_file \
  "https://github.com/LNH-team/pico-launcher/releases/latest/download/Pico_Launcher.zip" \
  "$INPUT_DIR/releases/Pico_Launcher.zip"

download_file \
  "https://github.com/LNH-team/dspico-usb-examples/releases/latest/download/mass-storage.nds" \
  "$INPUT_DIR/releases/mass-storage.nds"

if [ -z "$GBARUNNER2_URL" ]; then
  GBARUNNER2_URL="$(latest_gbarunner2_url)"
fi
[ -n "$GBARUNNER2_URL" ] || {
  echo "ERROR: Could not resolve latest GBARunner2 arm9dldi ds URL" >&2
  exit 1
}
download_file \
  "$GBARUNNER2_URL" \
  "$gbarunner2_nds"
cp -f "$gbarunner2_nds" "$INPUT_DIR/releases/GBARunner2.nds"

echo "Inputs are ready in $INPUT_DIR"

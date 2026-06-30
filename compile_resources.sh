#!/bin/bash
set -eu

# =============================================================================
#  DSpico Resources Compiler
# =============================================================================
#  Builds all DSpico components inside the Docker container.
#
#  Expected mounts:
#    /inputs  (read-only)  - Blowfish tables and optional inputs
#    /outputs              - Build artifacts destination
# =============================================================================

# ─── Configuration ────────────────────────────────────────────────────────────

OUT_BASE=/outputs/dspico
DLDITOOL="${DLDITOOL:-/opt/wonderful/thirdparty/blocksds/core/tools/dlditool/dlditool}"
: "${DSPICO_BOOTLOADER_REPO:?DSPICO_BOOTLOADER_REPO is required}"
: "${DSPICO_BOOTLOADER_REF:?DSPICO_BOOTLOADER_REF is required}"
: "${DSROMENCRYPTOR_REPO:?DSROMENCRYPTOR_REPO is required}"
: "${DSROMENCRYPTOR_REF:?DSROMENCRYPTOR_REF is required}"
: "${DSPICO_WRFUXXED_REPO:?DSPICO_WRFUXXED_REPO is required}"
: "${DSPICO_WRFUXXED_REF:?DSPICO_WRFUXXED_REF is required}"
: "${DSPICO_FIRMWARE_REPO:?DSPICO_FIRMWARE_REPO is required}"
: "${DSPICO_FIRMWARE_REF:?DSPICO_FIRMWARE_REF is required}"
: "${FIRM_TO_NDS_REPO:?FIRM_TO_NDS_REPO is required}"
: "${FIRM_TO_NDS_REF:?FIRM_TO_NDS_REF is required}"
DSPICO_FIRMWARE_EXTRA_REFS=${DSPICO_FIRMWARE_EXTRA_REFS:-}

# ─── ANSI Colors ──────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# ─── Shared state across build steps ─────────────────────────────────────────

DLDI_FILE=""
BOOTLOADER_NDS=""
ENCRYPTED_NDS=""
ENCRYPTOR_BIN=""

# =============================================================================
#  Utility functions
# =============================================================================

error_exit() {
	echo -e "${RED}ERROR: $1${NC}" >&2
	exit 1
}

info() { echo -e "${GREEN}$1${NC}"; }
warn() { echo -e "${YELLOW}$1${NC}"; }
step() { echo -e "\n${GREEN}[$1]${NC} $2"; }

# Clone a git repo into a writable build directory, check out a ref, and cd into it.
clone_repo() {
	local url="$1" dir="$2" ref="$3"
	rm -rf "$dir"
	git clone "$url" "$dir"
	cd "$dir"
	git checkout "$ref"
	git submodule update --init
}

merge_extra_refs() {
	local ref
	git config user.name "dspico-builder"
	git config user.email "dspico-builder@example.invalid"
	for ref in $1; do
		[ -n "$ref" ] || continue
		git fetch origin "$ref"
		git merge --no-edit FETCH_HEAD
	done
}

# Build with male (wonderful) or fall back to make.
build() {
	if command -v male >/dev/null 2>&1; then
		echo "Building with male..."
		male
	else
		echo "Building with make..."
		make -j"$(nproc)"
	fi
}

# Find a single file matching a pattern; error_exit if not found.
find_artifact() {
	local dir="$1" pattern="$2" depth="${3:-2}"
	local result
	result=$(find "$dir" -maxdepth "$depth" -name "$pattern" -type f | head -n 1)
	[ -n "$result" ] || error_exit "Artifact '$pattern' not found in $dir"
	echo "$result"
}

# Write BUILD_INFO.txt with commit metadata for the component.
write_build_info() {
	local repo_dir="$1" output_dir="$2" component="$3"
	local commit="local source, commit unavailable"
	local date="unknown"
	local summary="unknown"
	if git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		commit=$(git -C "$repo_dir" log -1 --format="%H" 2>/dev/null || echo "$commit")
		date=$(git -C "$repo_dir" log -1 --format="%ai" 2>/dev/null || echo "$date")
		summary=$(git -C "$repo_dir" log -1 --format="%s" 2>/dev/null || echo "$summary")
	fi
	cat >"$output_dir/BUILD_INFO.txt" <<EOF
Component: $component
Commit:    $commit
Date:      $date
Summary:   $summary
EOF
}

# Copy files matching a glob pattern (unquoted for expansion).
copy_glob() {
	local pattern="$1" dest="$2"
	for f in $pattern; do
		[ -e "$f" ] && cp -v "$f" "$dest"
	done
}

# Copy a file only if it exists.
copy_if_exists() {
	if [ -e "$1" ]; then
		cp -v "$1" "$2"
	fi
}

require_file() {
	[ -f "$1" ] || error_exit "$2 not found: $1"
}

prepare_ntrboot_roms() {
	local repo="$1"

	if [ "${ENABLE_NTRBOOT:-0}" != "1" ]; then
		return
	fi

	grep -R "ENABLE_NTRBOOT_AUTO_DETECTION" "$repo/CMakeLists.txt" "$repo/src" >/dev/null 2>&1 ||
		error_exit "ENABLE_NTRBOOT=1 requires dspico-firmware with ntrboot auto-detection support (upstream PR #8)"

	mkdir -p "$OUT_BASE/ntrboot"

	require_file /inputs/ntrboot/boot9strap_ntr.firm "boot9strap NTR FIRM"
	require_file /inputs/ntrboot/default.gcd "DSi ntrboot GCD"

	local firm_tool_repo=/tmp/firm-to-nds
	clone_repo "$FIRM_TO_NDS_REPO" "$firm_tool_repo" "$FIRM_TO_NDS_REF"
	cd "$repo"
	local firm_tool="$firm_tool_repo/firm_to_nds.py"
	[ -f "$firm_tool" ] || error_exit "firm-to-nds script not found at $firm_tool"
	python3 "$firm_tool" /inputs/ntrboot/boot9strap_ntr.firm "$repo/roms/ntrboot.nds" ||
		error_exit "firm-to-nds conversion failed for boot9strap_ntr.firm"
	cp -v "$repo/roms/ntrboot.nds" "$OUT_BASE/ntrboot/ntrboot.nds"
	info "  ✓ 3DS ntrboot image prepared as roms/ntrboot.nds"

	cp -v /inputs/ntrboot/default.gcd "$repo/roms/ntrbootdsi.nds"
	cp -v "$repo/roms/ntrbootdsi.nds" "$OUT_BASE/ntrboot/ntrbootdsi.nds"
	info "  ✓ DSi ntrboot image prepared as roms/ntrbootdsi.nds"
}

# Encrypt an NDS ROM using DSRomEncryptor (inserts blowfish tables + encrypts secure area).
# Automatically pads ROMs smaller than 32KB, as DSRomEncryptor writes test patterns
# (0x3000-0x3FFF) and processes the secure area (0x4000-0x8000).
encrypt_rom() {
	local input="$1" output="$2"
	[ -n "$ENCRYPTOR_BIN" ] || error_exit "DSRomEncryptor not available (did step_encryptor run?)"

	# DSRomEncryptor requires at least 0x8000 (32768) bytes for secure area processing.
	local work_input="$input"
	local rom_size
	rom_size=$(stat -c%s "$input")
	if [ "$rom_size" -lt 32768 ]; then
		work_input="/tmp/$(basename "$input" .nds)_padded.nds"
		cp "$input" "$work_input"
		truncate -s 32768 "$work_input"
		warn "⚠ Padded ROM from ${rom_size} to 32768 bytes for encryption"
	fi

	case "$ENCRYPTOR_BIN" in
	*.dll) dotnet "$ENCRYPTOR_BIN" "$work_input" "$output" ;;
	*) "$ENCRYPTOR_BIN" "$work_input" "$output" ;;
	esac || error_exit "Encryption failed for $(basename "$input")"
	[ -f "$output" ] || error_exit "Encrypted ROM not produced: $output"
}

# Compute total step count based on enabled features.
compute_steps() {
	TOTAL_STEPS=7
}

# Create the output directory tree.
setup_dirs() {
	local dirs="dldi bootloader encryptor firmware pico-loader pico-launcher wrfuxxed"
	if [ "${ENABLE_NTRBOOT:-0}" = "1" ]; then
		dirs="$dirs ntrboot"
	fi
	mkdir -p "$OUT_BASE"
	for d in $dirs; do
		mkdir -p "$OUT_BASE/$d"
	done
}

# =============================================================================
#  Build steps
# =============================================================================

# ── [1/7] DLDI driver release ────────────────────────────────────────────────

step_dldi() {
	step "1/$TOTAL_STEPS" "Install DSpico DLDI release"

	DLDI_FILE=/inputs/releases/DSpico.dldi
	[ -f "$DLDI_FILE" ] || error_exit "DLDI release asset not found: $DLDI_FILE"

	cp -v "$DLDI_FILE" "$OUT_BASE/dldi/"
	DLDI_FILE="$OUT_BASE/dldi/$(basename "$DLDI_FILE")"

	cat >"$OUT_BASE/dldi/BUILD_INFO.txt" <<EOF
Component: dspico-dldi
Source:    GitHub latest release asset
Asset:     DSpico.dldi
EOF
	info "✓ DLDI installed: $DLDI_FILE"
}

# ── [2/7] Bootloader (+ DLDI patch) ──────────────────────────────────────────

step_bootloader() {
	local repo=/tmp/dspico-bootloader
	step "2/$TOTAL_STEPS" "Build DSpico Bootloader"

	clone_repo "$DSPICO_BOOTLOADER_REPO" "$repo" "$DSPICO_BOOTLOADER_REF"
	build

	# Try BOOTLOADER.nds first, fall back to any .nds
	BOOTLOADER_NDS=$(find "$repo" -maxdepth 2 -name "BOOTLOADER.nds" -type f | head -n 1)
	# [ -n "$BOOTLOADER_NDS" ] || \
	# BOOTLOADER_NDS=$(find "$repo" -maxdepth 2 -name "*.nds" -type f | head -n 1)
	[ -n "$BOOTLOADER_NDS" ] || error_exit "No bootloader .nds file produced"

	[ -x "$DLDITOOL" ] || error_exit "DLDITOOL not found at: $DLDITOOL"
	"$DLDITOOL" "$DLDI_FILE" "$BOOTLOADER_NDS" || error_exit "DLDI patch failed on bootloader"

	cp -v "$BOOTLOADER_NDS" "$OUT_BASE/bootloader/"
	write_build_info "$repo" "$OUT_BASE/bootloader" "dspico-bootloader"
	info "✓ Bootloader built and patched"
}

# ── [3/7] DSRomEncryptor (encrypt bootloader) ────────────────────────────────

step_encryptor() {
	local repo=/tmp/DSRomEncryptor
	local bin_dir="$repo/DSRomEncryptor/bin/Debug/net9.0"
	step "3/$TOTAL_STEPS" "Build DSRomEncryptor"

	clone_repo "$DSROMENCRYPTOR_REPO" "$repo" "$DSROMENCRYPTOR_REF"
	dotnet build || error_exit "DSRomEncryptor build failed"
	[ -d "$bin_dir" ] || error_exit "Build output not found at $bin_dir"

	# Copy Blowfish tables from inputs
	if [ -d /inputs/blowfish ]; then
		echo "Copying Blowfish tables..."
		for f in /inputs/blowfish/*; do
			[ -f "$f" ] && cp -v "$f" "$bin_dir/" || true
		done
	fi

	# Validate Blowfish availability
	local ntr_ok=0 twl_ok=0
	if [ -f "$bin_dir/ntrBlowfish.bin" ] || [ -f "$bin_dir/biosnds7.rom" ]; then
		ntr_ok=1
	fi
	if [ -f "$bin_dir/twlBlowfish.bin" ] || [ -f "$bin_dir/biosdsi7.rom" ]; then
		twl_ok=1
	fi
	[ "$ntr_ok" -eq 1 ] || error_exit "NTR Blowfish not found (need ntrBlowfish.bin or biosnds7.rom in inputs/blowfish/)"
	[ "$twl_ok" -eq 1 ] || warn "⚠ TWL Blowfish not found (twlBlowfish.bin or biosdsi7.rom)"

	# Locate encryptor binary for reuse in later steps
	if [ -f "$bin_dir/DSRomEncryptor" ]; then
		ENCRYPTOR_BIN="$bin_dir/DSRomEncryptor"
	elif [ -f "$bin_dir/DSRomEncryptor.dll" ]; then
		ENCRYPTOR_BIN="$bin_dir/DSRomEncryptor.dll"
	else
		error_exit "DSRomEncryptor executable not found in $bin_dir"
	fi

	# Encrypt bootloader
	ENCRYPTED_NDS="$repo/default.nds"
	encrypt_rom "$BOOTLOADER_NDS" "$ENCRYPTED_NDS"
	cp -v "$ENCRYPTED_NDS" "$OUT_BASE/encryptor/"

	write_build_info "$repo" "$OUT_BASE/encryptor" "DSRomEncryptor"
	info "✓ Bootloader encrypted"
}

# ── [4/7] WRFUxxed (optional) ────────────────────────────────────────────────

step_wrfuxxed() {
	step "4/$TOTAL_STEPS" "Build WRFUxxed (optional)"

	if [ "${ENABLE_WRFUXXED:-0}" != "1" ]; then
		warn "⊗ Skipped (set ENABLE_WRFUXXED=1 to enable)"
		return
	fi

	local repo=/tmp/dspico-wrfuxxed
	clone_repo "$DSPICO_WRFUXXED_REPO" "$repo" "$DSPICO_WRFUXXED_REF"
	build

	local wrf_bin
	wrf_bin=$(find_artifact "$repo" "uartBufv060.bin")
	"$DLDITOOL" "$DLDI_FILE" "$wrf_bin" || error_exit "DLDI patch failed on wrfuxxed"

	cp -v "$wrf_bin" "$OUT_BASE/wrfuxxed/"
	write_build_info "$repo" "$OUT_BASE/wrfuxxed" "dspico-wrfuxxed"
	info "✓ WRFUxxed built and patched"
}

# ── [5/7] Firmware ────────────────────────────────────────────────────────────

step_firmware() {
	local repo=/tmp/dspico-firmware
	step "5/$TOTAL_STEPS" "Build DSpico Firmware"

	clone_repo "$DSPICO_FIRMWARE_REPO" "$repo" "$DSPICO_FIRMWARE_REF"
	merge_extra_refs "$DSPICO_FIRMWARE_EXTRA_REFS"
	(cd pico-sdk && git submodule update --init)

	# Normal mode: inject encrypted bootloader
	[ -f "$ENCRYPTED_NDS" ] || error_exit "default.nds not available"
	cp -v "$ENCRYPTED_NDS" "$repo/roms/default.nds"

	# WRFUxxed integration
	if [ "${ENABLE_WRFUXXED:-0}" = "1" ]; then
		require_file /inputs/wrfuxxed/dsimode.nds "WRFUxxed DSi mode ROM"
		cp -v /inputs/wrfuxxed/dsimode.nds "$repo/roms/dsimode.nds"
		copy_if_exists /tmp/dspico-wrfuxxed/uartBufv060.bin "$repo/data/uartBufv060.bin"
		if ! grep -q "data/uartBufv060.bin" CMakeLists.txt; then
			# Older firmware revisions need this define uncommented manually.
			sed -i 's/^\(\s*\)#\s*\(DSPICO_ENABLE_WRFUXXED\)/\1\2/' CMakeLists.txt || true
		fi
	fi

	prepare_ntrboot_roms "$repo"

	chmod +x compile.sh
	./compile.sh || error_exit "Firmware compilation failed"

	find_artifact "$repo/build" "*.uf2" >/dev/null
	copy_glob "$repo/build/*.uf2" "$OUT_BASE/firmware/"

	write_build_info "$repo" "$OUT_BASE/firmware" "dspico-firmware"
	info "✓ Firmware built"
}

# ── [6/7] Pico Loader and Launcher releases ──────────────────────────────────

step_sd_releases() {
	step "6/$TOTAL_STEPS" "Install Pico Loader and Launcher releases"

	local loader_zip=/inputs/releases/Pico_Loader_DSPICO.zip
	local launcher_zip=/inputs/releases/Pico_Launcher.zip

	[ -f "$loader_zip" ] || error_exit "Pico Loader release asset not found: $loader_zip"
	[ -f "$launcher_zip" ] || error_exit "Pico Launcher release asset not found: $launcher_zip"

	unzip -oq "$loader_zip" -d "$OUT_BASE/pico-loader"
	unzip -oq "$launcher_zip" -d "$OUT_BASE/pico-launcher"

	find_artifact "$OUT_BASE/pico-loader" "picoLoader7.bin" 1 >/dev/null
	find_artifact "$OUT_BASE/pico-loader" "picoLoader9.bin" 1 >/dev/null
	find_artifact "$OUT_BASE/pico-launcher" "LAUNCHER.nds" 1 >/dev/null
	[ -d "$OUT_BASE/pico-launcher/_pico" ] || error_exit "Pico Launcher _pico directory not found"

	cat >"$OUT_BASE/pico-loader/BUILD_INFO.txt" <<EOF
Component: pico-loader
Source:    GitHub latest release asset
Asset:     Pico_Loader_DSPICO.zip
EOF
	cat >"$OUT_BASE/pico-launcher/BUILD_INFO.txt" <<EOF
Component: pico-launcher
Source:    GitHub latest release asset
Asset:     Pico_Launcher.zip
EOF

	info "✓ Pico Loader and Launcher installed"
}

# ── [7/7] Assemble SD card ───────────────────────────────────────────────────

step_assemble_sd() {
	step "7/$TOTAL_STEPS" "Assemble SD card structure"

	local sd="$OUT_BASE/sd_card"
	rm -rf "$sd"
	mkdir -p "$sd/_pico" "$sd/Emulators" "$sd/gba" "$sd/nds" "$sd/dsi"

	# Copy _pico contents from pico-launcher
	if [ -d "$OUT_BASE/pico-launcher/_pico" ]; then
		cp -r "$OUT_BASE/pico-launcher/_pico"/* "$sd/_pico/" || true
	fi

	# Copy pico loader binaries
	if [ -d "$OUT_BASE/pico-loader" ]; then
		copy_glob "$OUT_BASE/pico-loader/picoLoader7*.bin" "$sd/_pico/"
		for f in "$OUT_BASE/pico-loader"/picoLoader9*.bin; do
			if [ -e "$f" ]; then
				cp -v "$f" "$sd/_pico/picoLoader9.bin"
				break
			fi
		done
		copy_if_exists "$OUT_BASE/pico-loader/aplist.bin" "$sd/_pico/aplist.bin"
		copy_if_exists "$OUT_BASE/pico-loader/savelist.bin" "$sd/_pico/savelist.bin"
		copy_if_exists "$OUT_BASE/pico-loader/patchlist.bin" "$sd/_pico/patchlist.bin"
	fi

	# Set LAUNCHER.nds as boot file
	[ -f "$OUT_BASE/pico-launcher/LAUNCHER.nds" ] ||
		error_exit "LAUNCHER.nds not found for SD card assembly"
	cp -v "$OUT_BASE/pico-launcher/LAUNCHER.nds" "$sd/_picoboot.nds"

	[ -f /inputs/bios/biosnds7.rom ] || error_exit "DS ARM7 BIOS not found: /inputs/bios/biosnds7.rom"
	[ -f /inputs/bios/bios.bin ] || error_exit "GBA BIOS not found: /inputs/bios/bios.bin"
	[ -f /inputs/releases/GBARunner2.nds ] || error_exit "GBARunner2.nds not found: /inputs/releases/GBARunner2.nds"
	cp -v /inputs/bios/biosnds7.rom "$sd/_pico/biosnds7.rom"
	cp -v /inputs/bios/bios.bin "$sd/bios.bin"
	cp -v /inputs/releases/GBARunner2.nds "$sd/Emulators/GBARunner2.nds"

	if [ -f /inputs/releases/mass-storage.nds ]; then
		mkdir -p "$sd/roms"
		cp -v /inputs/releases/mass-storage.nds "$sd/roms/mass-storage.nds"
	else
		warn "⚠ mass-storage.nds release asset not found; skipping SD card tools copy"
	fi

	info "✓ SD card assembled: $sd"
}

# =============================================================================
#  Main
# =============================================================================

main() {
	compute_steps
	setup_dirs
	[ -f /opt/wonderful/bin/wf-env ] && . /opt/wonderful/bin/wf-env || true

	step_dldi
	step_bootloader
	step_encryptor
	step_wrfuxxed
	step_firmware
	step_sd_releases
	step_assemble_sd

	echo ""
	info "════════════════════════════════════════"
	info "  All components built successfully!"
	[ -f "$OUT_BASE/firmware/DSpico.uf2" ] && info "  firmware: outputs/dspico/firmware/DSpico.uf2"
	info "════════════════════════════════════════"
	echo "Outputs: $OUT_BASE"
}

main "$@"

# DSpico Resources Compiler

Build a combined DSpico firmware package from local input files, latest release
assets, and patched upstream firmware sources.

## Inputs

Prepare the local input files before building:

- required binary inputs such as Blowfish tables, WRFU, and DSi ntrboot
  payloads
- BIOS files used by Pico Loader and GBARunner2
- unpinned generated/downloaded inputs such as boot9strap NTR FIRM
- latest release assets used directly by the build:
  - `DSpico.dldi`
  - `Pico_Loader_DSPICO.zip`
  - `Pico_Launcher.zip`
  - `mass-storage.nds`
  - `GBARunner2.nds`

The build does not vendor upstream source repositories. It clones only the
repositories that still need to be built or patched.

## Prepare Inputs

Run:

```bash
bash scripts/fetch_inputs.sh
```

If GitHub API rate limiting blocks latest-release lookup, pass a token:

```bash
GITHUB_TOKEN=ghp_xxx bash scripts/fetch_inputs.sh
```

`GH_TOKEN` is also accepted.

This downloads:

```text
inputs/blowfish/ntrBlowfish.bin
inputs/blowfish/twlBlowfish.bin
inputs/wrfuxxed/dsimode.nds
inputs/bios/biosnds7.rom
inputs/bios/bios.bin
inputs/ntrboot/boot9strap_ntr.firm
inputs/ntrboot/default.gcd
inputs/releases/DSpico.dldi
inputs/releases/Pico_Loader_DSPICO.zip
inputs/releases/Pico_Launcher.zip
inputs/releases/mass-storage.nds
inputs/releases/GBARunner2.nds
```

The fixed non-release payloads are SHA1-verified. Release assets and boot9strap
use latest upstream releases and are not version-locked.

## Input Download Reference

`scripts/fetch_inputs.sh` downloads these files. The URLs are documented here
so the files can also be prepared or replaced manually.

| File | Destination | URL | SHA1 policy |
| --- | --- | --- | --- |
| WRFU Tester v0.60 fixed | `inputs/wrfuxxed/dsimode.nds` | `https://archive.org/download/wrfu_0.60_fixed/wrfu.srl` | `2d65fb7a0c62a4f08954b98c95f42b804fccfd26` |
| NTR Blowfish table | `inputs/blowfish/ntrBlowfish.bin` | `https://github.com/DS-Homebrew/nds-bootstrap/raw/342b9408f761c1f3f03aac154c9e0aab1707e10f/retail/nitrofiles/encr_data.bin` | `84e467f2485078e401a17a5f231e3fe6e9686648` |
| TWL Blowfish table | `inputs/blowfish/twlBlowfish.bin` | `https://github.com/DS-Homebrew/nds-bootstrap/raw/342b9408f761c1f3f03aac154c9e0aab1707e10f/retail/nitrofiles/dsi_encr_data.bin` | `2dea11191f28c6cc1956dadb8941affd4b2b5102` |
| DS ARM7 BIOS | `inputs/bios/biosnds7.rom` | `https://archive.org/download/nds-bios-firmware/bios7.bin` | `24f67bdea115a2c847c8813a262502ee1607b7df` |
| GBA BIOS | `inputs/bios/bios.bin` | `https://archive.org/download/gba_bios_202501/gba_bios.zip` (`gba_bios.bin` inside zip) | `300c20df6731a33952ded8c436f7f186d25d3492` |
| boot9strap NTR FIRM | `inputs/ntrboot/boot9strap_ntr.firm` | latest `boot9strap-*-ntr.zip` from `https://api.github.com/repos/SciresM/boot9strap/releases/latest` | latest release, not pinned |
| DSi ntrboot GCD | `inputs/ntrboot/default.gcd` | `https://wiki.ds-homebrew.com/assets/files/default.gcd` | `eca89918bbff09090a43e67f2805d9743e2ac343` |
| DSpico DLDI | `inputs/releases/DSpico.dldi` | `https://github.com/LNH-team/dspico-dldi/releases/latest/download/DSpico.dldi` | latest release, not pinned |
| Pico Loader DSPICO package | `inputs/releases/Pico_Loader_DSPICO.zip` | `https://github.com/LNH-team/pico-loader/releases/latest/download/Pico_Loader_DSPICO.zip` | latest release, not pinned |
| Pico Launcher package | `inputs/releases/Pico_Launcher.zip` | `https://github.com/LNH-team/pico-launcher/releases/latest/download/Pico_Launcher.zip` | latest release, not pinned |
| DSpico USB mass storage tool | `inputs/releases/mass-storage.nds` | `https://github.com/LNH-team/dspico-usb-examples/releases/latest/download/mass-storage.nds` | latest release, not pinned |
| GBARunner2 | `inputs/releases/GBARunner2.nds` | latest `GBARunner2_arm9dldi_ds.nds` from `https://api.github.com/repos/Gericom/GBARunner2/releases/latest`, renamed locally | latest release, not pinned |

## Source Repositories Used During Build

These repositories are cloned inside the build container:

- `dspico-bootloader`
- `DSRomEncryptor`
- `dspico-wrfuxxed`
- `dspico-firmware`
- `firm-to-nds`

The following components are used from release assets instead of source builds:

- `dspico-dldi`
- `pico-loader`
- `pico-launcher`
- `dspico-usb-examples` mass storage tool
- `GBARunner2`

## Firmware Patch Inputs

By default, `dspico-firmware` is cloned from upstream `develop` without merging
extra refs. Specify firmware PRs manually for builds that need them.

Known useful upstream PR refs:

- `pull/8/head`: ntrboot auto detection
- `pull/18/head`: auto-enable WRFUxxed when `uartBufv060.bin` exists
- `pull/19/head`: Pico SDK 2.x compatibility

Build with those PRs:

```bash
DSPICO_FIRMWARE_EXTRA_REFS="pull/8/head pull/18/head pull/19/head" \
ENABLE_WRFUXXED=1 ENABLE_NTRBOOT=1 \
./build_resources.sh
```

Override sources with environment variables:

```bash
DSPICO_FIRMWARE_REPO=https://github.com/yourname/dspico-firmware.git \
DSPICO_FIRMWARE_REF=my-branch \
ENABLE_WRFUXXED=1 ENABLE_NTRBOOT=1 \
./build_resources.sh
```

Available source overrides:

```text
DSPICO_BOOTLOADER_REPO
DSPICO_BOOTLOADER_REF
DSROMENCRYPTOR_REPO
DSROMENCRYPTOR_REF
DSPICO_WRFUXXED_REPO
DSPICO_WRFUXXED_REF
DSPICO_FIRMWARE_REPO
DSPICO_FIRMWARE_REF
DSPICO_FIRMWARE_EXTRA_REFS
FIRM_TO_NDS_REPO
FIRM_TO_NDS_REF
```

`DSPICO_FIRMWARE_EXTRA_REFS` is a space-separated list of refs fetched from the
same firmware repository and merged in order.

## Build

On a Docker-capable Linux/x86_64 machine:

Use upstream `dspico-firmware` with the useful PRs merged at build time:

```bash
DSPICO_FIRMWARE_EXTRA_REFS="pull/8/head pull/18/head pull/19/head" \
ENABLE_WRFUXXED=1 ENABLE_NTRBOOT=1 \
./build_resources.sh
```

Use the maintained fork with those changes already merged:

```bash
DSPICO_FIRMWARE_REPO=https://github.com/dev-soragoto/dspico-firmware.git \
DSPICO_FIRMWARE_REF=develop \
ENABLE_WRFUXXED=1 ENABLE_NTRBOOT=1 \
./build_resources.sh
```

Optional custom paths:

```bash
DSPICO_FIRMWARE_REPO=https://github.com/dev-soragoto/dspico-firmware.git \
DSPICO_FIRMWARE_REF=develop \
ENABLE_WRFUXXED=1 ENABLE_NTRBOOT=1 \
./build_resources.sh /path/to/inputs /path/to/outputs
```

## GitHub Actions

Run **Build DSpico Package** from the Actions tab. The workflow is manual only
and uploads two artifacts:

- `DSpico.uf2`
- `sd_root` with the SD card root files

Fill in the firmware source when starting the workflow.

For upstream plus manually merged PR refs:

```text
firmware_repo: https://github.com/LNH-team/dspico-firmware.git
firmware_ref: develop
firmware_extra_refs: pull/8/head pull/18/head pull/19/head
```

To build from a fork with those changes already merged, use:

```text
firmware_repo: https://github.com/dev-soragoto/dspico-firmware.git
firmware_ref: develop
firmware_extra_refs:
```

## ntrboot Auto Detection

With `ENABLE_NTRBOOT=1`, the build embeds ntrboot images using the names
expected by the firmware auto-detection feature:

- `inputs/ntrboot/boot9strap_ntr.firm` is converted to `roms/ntrboot.nds`
- `inputs/ntrboot/default.gcd` is copied to `roms/ntrbootdsi.nds` when the 3DS
  ntrboot image also exists

Both files are required when `ENABLE_NTRBOOT=1`; the build fails immediately if
either input is missing.

With `ENABLE_WRFUXXED=1`, `inputs/wrfuxxed/dsimode.nds` is also required. The
build fails immediately if it is missing.

The old separate `DSpico_ntrboot_3ds.uf2` and `DSpico_ntrboot_dsi.uf2` outputs
are not expected with the auto-detection firmware.

## Outputs

Primary outputs are written under:

```text
outputs/dspico/
├── firmware/
│   └── DSpico.uf2
├── sd_card/
│   ├── _picoboot.nds
│   ├── _pico/
│   │   ├── aplist.bin
│   │   ├── patchlist.bin
│   │   ├── picoLoader7.bin
│   │   ├── picoLoader9.bin
│   │   ├── savelist.bin
│   │   ├── biosnds7.rom
│   │   └── themes/
│   ├── Emulators/
│   │   └── GBARunner2.nds
│   ├── gba/
│   ├── nds/
│   ├── dsi/
│   ├── bios.bin
│   └── roms/mass-storage.nds
├── bootloader/
├── dldi/
├── encryptor/
├── ntrboot/
├── pico-loader/
├── pico-launcher/
└── wrfuxxed/
```

Use `outputs/dspico/firmware/DSpico.uf2` as the combined firmware. Copy
`outputs/dspico/sd_card/` to the SD card.

Suggested ROM placement:

- put GBA games in `gba/`
- put NDS games in `nds/`
- put DSiWare and DSi-related `.nds` files in `dsi/`

`Emulators/GBARunner2.nds` is the upstream `GBARunner2_arm9dldi_ds.nds` build
renamed for the SD card. This is the DS-mode DLDI build, which matches the
DSpico flashcard use case.

## Notes

- Run `scripts/fetch_inputs.sh` again when refreshing local inputs.
- Release assets use latest versions by default. If upstream changes break the
  package layout, pin or replace the file in `inputs/releases/` manually.
- GBARunner3 is not included because it currently has no stable release assets
  to download.

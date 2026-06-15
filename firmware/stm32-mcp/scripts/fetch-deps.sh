#!/usr/bin/env bash
# fetch-deps.sh — Fetch vendor dependencies not tracked in git.
#
# Usage: ./scripts/fetch-deps.sh [--vl53l8cx-path /path/to/stsw-img040]
#
# Clones STM32CubeL4 from GitHub (no login required).
# VL53L8CX requires a manual download from st.com; see --vl53l8cx-path.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "--- $*"; }

# ── Parse args ────────────────────────────────────────────────────────────────
VL53L8CX_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vl53l8cx-path) VL53L8CX_PATH="$2"; shift 2 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# ── 1. STM32CubeL4 (CMSIS + HAL + BLE) ───────────────────────────────────────
info "Cloning STM32CubeL4 (shallow) ..."
CUBE_DIR="$TMPDIR_BASE/STM32CubeL4"
git clone --depth 1 \
  https://github.com/STMicroelectronics/STM32CubeL4 \
  "$CUBE_DIR"

# CMSIS core headers
info "Installing CMSIS/Include ..."
rm -rf "$ROOT/Drivers/CMSIS/Include"
cp -r "$CUBE_DIR/Drivers/CMSIS/Include" "$ROOT/Drivers/CMSIS/"

# CMSIS Device (STM32L4xx only)
info "Installing CMSIS/Device/ST/STM32L4xx ..."
rm -rf "$ROOT/Drivers/CMSIS/Device"
mkdir -p "$ROOT/Drivers/CMSIS/Device/ST"
cp -r "$CUBE_DIR/Drivers/CMSIS/Device/ST/STM32L4xx" \
      "$ROOT/Drivers/CMSIS/Device/ST/"

# STM32L4xx HAL driver
info "Installing STM32L4xx_HAL_Driver ..."
rm -rf "$ROOT/Drivers/STM32L4xx_HAL_Driver"
cp -r "$CUBE_DIR/Drivers/STM32L4xx_HAL_Driver" "$ROOT/Drivers/"

# BLE middleware from P2P_LedButton example
info "Installing BLE middleware ..."
EXAMPLE="$CUBE_DIR/Projects/B-L475E-IOT01A/Applications/BLE/P2P_LedButton"
MIDDLEWARE="$CUBE_DIR/Middlewares/ST/BlueNRG-MS"

mkdir -p "$ROOT/BLE/"{ble_core,ble_services,hw,tl,utilities,debug,_reference}

# BlueNRG-MS ACI + HCI layer
cp "$MIDDLEWARE"/hci/*.c         "$ROOT/BLE/ble_core/" 2>/dev/null || true
cp "$MIDDLEWARE"/hci/*.h         "$ROOT/BLE/ble_core/" 2>/dev/null || true
cp "$MIDDLEWARE"/includes/*.h    "$ROOT/BLE/ble_core/" 2>/dev/null || true

# Transport layer
cp "$EXAMPLE"/BLE_Application/TL/tl_ble_*.c  "$ROOT/BLE/tl/" 2>/dev/null || true
cp "$EXAMPLE"/BLE_Application/TL/tl_ble_*.h  "$ROOT/BLE/tl/" 2>/dev/null || true

# HW abstraction
cp "$EXAMPLE"/BLE_Application/hw_*.c  "$ROOT/BLE/hw/" 2>/dev/null || true
cp "$EXAMPLE"/BLE_Application/hw_*.h  "$ROOT/BLE/hw/" 2>/dev/null || true

# Utilities
find "$EXAMPLE"/BLE_Application -maxdepth 2 -name "osal.*" \
     -o -name "stm32_seq.*" | while read f; do
  cp "$f" "$ROOT/BLE/utilities/" 2>/dev/null || true
done

# Reference snapshot
cp "$EXAMPLE"/Core/Src/main.c         "$ROOT/BLE/_reference/" 2>/dev/null || true
cp "$EXAMPLE"/Core/Src/stm32l4xx_it.c "$ROOT/BLE/_reference/" 2>/dev/null || true
cp "$EXAMPLE"/Core/Inc/*.h            "$ROOT/BLE/_reference/" 2>/dev/null || true

# ── 2. VL53L8CX ULD ───────────────────────────────────────────────────────────
if [[ -n "$VL53L8CX_PATH" ]]; then
  info "Installing VL53L8CX from $VL53L8CX_PATH ..."
  rm -rf "$ROOT/Drivers/VL53L8CX/modules"
  mkdir -p "$ROOT/Drivers/VL53L8CX"/{modules,platform}

  # Try common package layouts from STSW-IMG040.
  ULD="$VL53L8CX_PATH"
  if [[ -d "$ULD/Middlewares/ST/VL53L8CX_ULD" ]]; then
    ULD="$ULD/Middlewares/ST/VL53L8CX_ULD"
  elif [[ -d "$ULD/VL53L8CX_ULD" ]]; then
    ULD="$ULD/VL53L8CX_ULD"
  fi

  [[ -d "$ULD/modules" ]] || die "Cannot find VL53L8CX_ULD/modules under $VL53L8CX_PATH"
  [[ -d "$ULD/platform" ]] || die "Cannot find VL53L8CX_ULD/platform under $VL53L8CX_PATH"

  cp "$ULD"/modules/*.c  "$ROOT/Drivers/VL53L8CX/modules/" 2>/dev/null || true
  cp "$ULD"/modules/*.h  "$ROOT/Drivers/VL53L8CX/modules/" 2>/dev/null || true

  if [[ -f "$ROOT/Drivers/VL53L8CX/platform/platform.h" ]]; then
    echo "NOTE: Preserving existing VL53L8CX platform wrapper."
  else
    cp "$ULD"/platform/*.c "$ROOT/Drivers/VL53L8CX/platform/" 2>/dev/null || true
    cp "$ULD"/platform/*.h "$ROOT/Drivers/VL53L8CX/platform/" 2>/dev/null || true
  fi
else
  echo ""
  echo "VL53L8CX: REQUIRED - download STSW-IMG040 from:"
  echo "  https://www.st.com/en/embedded-software/stsw-img040.html"
  echo "Then re-run: $0 --vl53l8cx-path /path/to/extracted/stsw-img040"
  echo ""
fi

# ── Done ──────────────────────────────────────────────────────────────────────
info "Verifying installation ..."
errors=0
check() {
  if [[ ! -e "$1" ]]; then
    echo "MISSING: $1" >&2; errors=$((errors+1))
  fi
}

check "$ROOT/Drivers/CMSIS/Include/core_cm4.h"
check "$ROOT/Drivers/CMSIS/Device/ST/STM32L4xx/Include/stm32l475xx.h"
check "$ROOT/Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal.c"
check "$ROOT/BLE/ble_core/bluenrg_gap_aci.c"
check "$ROOT/BLE/tl/tl_ble_hci.c"
check "$ROOT/BLE/hw/hw_spi.c"
check "$ROOT/BLE/ble_services/svc_ctl.c"
check "$ROOT/BLE/utilities/scheduler.c"
check "$ROOT/Drivers/VL53L8CX/modules/vl53l8cx_api.h"
check "$ROOT/Drivers/VL53L8CX/platform/platform.h"

if [[ $errors -eq 0 ]]; then
  echo ""
  echo "All dependencies installed. Build with:"
  echo "  cd build/Debug && cmake --build ."
else
  echo "$errors file(s) missing — check the fetch output above." >&2
  exit 1
fi

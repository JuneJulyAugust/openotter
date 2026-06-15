#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# build.sh — Build and flash STM32L475 firmware using STM32CubeCLT
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}"
PROJECT_NAME="stm32-mcp"

# STM32CubeCLT installation root (adjust if your version differs)
CUBECLT_ROOT="${CUBECLT_ROOT:-/opt/st/STM32CubeCLT_1.21.0}"

# Tool paths derived from CubeCLT root
GCC_BIN="${CUBECLT_ROOT}/GNU-tools-for-STM32/bin"
NINJA_BIN="${CUBECLT_ROOT}/Ninja/bin"
CMAKE_BIN="${CUBECLT_ROOT}/CMake/bin"
PROGRAMMER="${CUBECLT_ROOT}/STM32CubeProgrammer/bin/STM32_Programmer_CLI"

# Build configuration: Debug or Release
BUILD_TYPE="${BUILD_TYPE:-Debug}"

# ST-Link connection parameters
STLINK_PORT="${STLINK_PORT:-SWD}"
STLINK_RESET="${STLINK_RESET:-SWrst}"

# Derived paths
BUILD_DIR="${PROJECT_DIR}/build/${BUILD_TYPE}"
ELF_FILE="${BUILD_DIR}/${PROJECT_NAME}.elf"
BIN_FILE="${BUILD_DIR}/${PROJECT_NAME}.bin"
HEX_FILE="${BUILD_DIR}/${PROJECT_NAME}.hex"

# ── Helpers ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── Precondition Checks ──────────────────────────────────────────────────────
check_prerequisites() {
    local missing=0

    if [[ ! -d "${CUBECLT_ROOT}" ]]; then
        error "STM32CubeCLT not found at ${CUBECLT_ROOT}"
        error "Set CUBECLT_ROOT to your installation path."
        exit 1
    fi

    for tool in "${GCC_BIN}/arm-none-eabi-gcc" "${NINJA_BIN}/ninja" "${CMAKE_BIN}/cmake"; do
        if [[ ! -x "${tool}" ]]; then
            error "Required tool not found: ${tool}"
            missing=1
        fi
    done

    if (( missing )); then
        exit 1
    fi

    # Export PATH so cmake/ninja/gcc are all discoverable
    export PATH="${GCC_BIN}:${NINJA_BIN}:${CMAKE_BIN}:${PATH}"
}

check_vendor_dependencies() {
    local missing=0
    local required=(
        "Drivers/CMSIS/Include/core_cm4.h"
        "Drivers/CMSIS/Device/ST/STM32L4xx/Include/stm32l475xx.h"
        "Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal.c"
        "BLE/ble_core/bluenrg_gap_aci.c"
        "BLE/tl/tl_ble_hci.c"
        "BLE/hw/hw_spi.c"
        "BLE/ble_services/svc_ctl.c"
        "BLE/utilities/scheduler.c"
        "Drivers/VL53L8CX/modules/vl53l8cx_api.h"
        "Drivers/VL53L8CX/platform/platform.h"
    )

    for rel in "${required[@]}"; do
        if [[ ! -e "${PROJECT_DIR}/${rel}" ]]; then
            error "Missing vendor dependency: ${rel}"
            missing=1
        fi
    done

    if (( missing )); then
        cat >&2 <<EOF

Vendor dependencies are intentionally not tracked in git.
Populate them before building this worktree:

  cd "${PROJECT_DIR}"
  bash scripts/fetch-deps.sh --vl53l8cx-path /path/to/extracted/STSW-IMG040

STM32CubeL4 and BlueNRG-MS are fetched automatically by that script.
VL53L8CX requires ST's manually downloaded STSW-IMG040 package.

EOF
        exit 1
    fi
}

# ── Build Steps ───────────────────────────────────────────────────────────────
do_configure() {
    info "Configuring ${BOLD}${BUILD_TYPE}${NC} build..."
    cmake --preset "${BUILD_TYPE}" -S "${PROJECT_DIR}"
    success "Configure complete."
}

do_build() {
    info "Building ${BOLD}${BUILD_TYPE}${NC} firmware..."
    cmake --build --preset "${BUILD_TYPE}"
    success "Build complete: ${ELF_FILE}"
}

do_generate_artifacts() {
    local objcopy="${GCC_BIN}/arm-none-eabi-objcopy"
    local size="${GCC_BIN}/arm-none-eabi-size"

    info "Generating binary artifacts..."

    "${objcopy}" -O binary "${ELF_FILE}" "${BIN_FILE}"
    success "Binary:  ${BIN_FILE}"

    "${objcopy}" -O ihex "${ELF_FILE}" "${HEX_FILE}"
    success "Intel HEX: ${HEX_FILE}"

    echo ""
    info "Firmware size:"
    "${size}" "${ELF_FILE}"
    echo ""
}

do_flash() {
    if [[ ! -x "${PROGRAMMER}" ]]; then
        error "STM32CubeProgrammer CLI not found at ${PROGRAMMER}"
        exit 1
    fi

    info "Flashing ${BOLD}${ELF_FILE}${NC} via ${STLINK_PORT}..."
    "${PROGRAMMER}" \
        --connect port="${STLINK_PORT}" reset="${STLINK_RESET}" \
        --download "${ELF_FILE}" \
        --verify \
        --go
    success "Flash and verify complete."
}

do_clean() {
    info "Cleaning build directory: ${BUILD_DIR}"
    rm -rf "${BUILD_DIR}"
    success "Clean complete."
}

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}Usage:${NC} $(basename "$0") [options] <command>

${BOLD}Commands:${NC}
  build       Configure, compile, and generate .bin/.hex artifacts (default)
  flash       Flash the firmware to the target via ST-Link
  all         Build then flash
  clean       Remove the build directory
  configure   Run CMake configure only
  artifacts   Generate .bin/.hex from existing .elf

${BOLD}Options:${NC}
  -r, --release     Build in Release mode (default: Debug)
  -h, --help        Show this help message

${BOLD}Environment:${NC}
  CUBECLT_ROOT      STM32CubeCLT install path (default: /opt/st/STM32CubeCLT_1.21.0)
  BUILD_TYPE        Debug or Release (default: Debug, overridden by -r)
  STLINK_PORT       Connection interface (default: SWD)
  STLINK_RESET      Reset mode (default: SWrst)

${BOLD}Examples:${NC}
  $(basename "$0")                  # Build Debug
  $(basename "$0") -r all           # Build Release and flash
  $(basename "$0") flash            # Flash last build
  BUILD_TYPE=Release $(basename "$0") clean  # Clean Release build
EOF
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--release)
                BUILD_TYPE="Release"
                BUILD_DIR="${PROJECT_DIR}/build/${BUILD_TYPE}"
                ELF_FILE="${BUILD_DIR}/${PROJECT_NAME}.elf"
                BIN_FILE="${BUILD_DIR}/${PROJECT_NAME}.bin"
                HEX_FILE="${BUILD_DIR}/${PROJECT_NAME}.hex"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                break
                ;;
        esac
    done

    local command="${1:-build}"

    check_prerequisites

    case "${command}" in
        configure)
            check_vendor_dependencies
            do_configure
            ;;
        build)
            check_vendor_dependencies
            do_configure
            do_build
            do_generate_artifacts
            ;;
        artifacts)
            if [[ ! -f "${ELF_FILE}" ]]; then
                error "ELF not found: ${ELF_FILE} — run 'build' first."
                exit 1
            fi
            do_generate_artifacts
            ;;
        flash)
            if [[ ! -f "${ELF_FILE}" ]]; then
                error "ELF not found: ${ELF_FILE} — run 'build' first."
                exit 1
            fi
            do_flash
            ;;
        all)
            check_vendor_dependencies
            do_configure
            do_build
            do_generate_artifacts
            do_flash
            ;;
        clean)
            do_clean
            ;;
        *)
            error "Unknown command: ${command}"
            usage
            exit 1
            ;;
    esac
}

main "$@"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

PROJECT_NAME="openotter"
SCHEME="$PROJECT_NAME"
CONFIG="${CONFIG:-Debug}"
DERIVED_DATA="$SCRIPT_DIR/.build/DerivedData"
BUNDLE_ID="com.openotter.app"

usage() {
    cat <<EOF
Usage: $0 <command> [options]

Commands:
  generate    Generate Xcode project from project.yml (requires xcodegen)
  build       Build the iOS app
  install     Install app on connected device
  launch      Launch app on connected device
  deploy      Build + install + launch (full cycle)
  test        Run unit tests on the iOS Simulator
  devices     List connected iOS devices
  simulators  List available iOS Simulators

Options:
  --device <UDID>   Target device UDID (auto-detected if one device connected)
  --release         Use Release configuration

Environment:
  DEVICE_UDID       Device UDID (alternative to --device flag)
  CONFIG            Build configuration (default: Debug)
  SIMULATOR_NAME    Preferred test simulator name (default: iPhone 17)
  SIMULATOR_UDID    Exact test simulator UDID
  TEST_DESTINATION  Full xcodebuild test destination override
EOF
    exit 1
}

# Parse global options
DEVICE_UDID="${DEVICE_UDID:-}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"
SIMULATOR_UDID="${SIMULATOR_UDID:-}"
TEST_DESTINATION="${TEST_DESTINATION:-}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --device) DEVICE_UDID="$2"; shift 2 ;;
        --release) CONFIG="Release"; shift ;;
        generate|build|install|launch|deploy|test|devices|simulators) COMMAND="$1"; shift; break ;;
        -h|--help) usage ;;
        *) echo "Unknown argument: $1"; usage ;;
    esac
done

COMMAND="${COMMAND:-}"
[[ -z "$COMMAND" ]] && usage

auto_detect_device() {
    if [[ -n "$DEVICE_UDID" ]]; then return; fi

    local devices
    devices=$(xcrun devicectl list devices 2>/dev/null \
        | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' || true)
    local count
    count=$(echo "$devices" | grep -c . 2>/dev/null || echo 0)

    if [[ "$count" -eq 1 ]]; then
        DEVICE_UDID="$(echo "$devices" | head -1 | xargs)"
        echo "Auto-detected device: $DEVICE_UDID"
    elif [[ "$count" -gt 1 ]]; then
        echo "Multiple devices found. Specify with --device <UDID>:"
        xcrun devicectl list devices 2>/dev/null
        exit 1
    else
        echo "No connected iOS devices found."
        exit 1
    fi
}

app_path() {
    echo "$DERIVED_DATA/Build/Products/$CONFIG-iphoneos/$PROJECT_NAME.app"
}

show_signing_hint() {
    cat <<'EOF'
Hint: this looks like a signing, provisioning, or device-trust issue.
1. In Xcode, confirm that the `openotter` target uses Automatic Signing and the correct Team.
2. If Xcode reports an expired profile or certificate, refresh it in Xcode > Settings > Accounts > Manage Certificates, then rebuild.
3. On the iPhone, enable Developer Mode in Settings > Privacy & Security.
4. If the device shows an untrusted developer profile, trust it in Settings > General > VPN & Device Management.
EOF
}

cmd_generate() {
    echo "==> Generating Xcode project..."
    export APP_VERSION=$(cat VERSION)
    xcodegen generate
    echo "==> Done: $PROJECT_NAME.xcodeproj"
}

cmd_build() {
    if [[ ! -d "$PROJECT_NAME.xcodeproj" ]]; then
        cmd_generate
    fi

    local team_arg=""
    if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
        team_arg="DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM"
    fi

    echo "==> Building $SCHEME ($CONFIG)..."
    local build_output
    build_output="$(mktemp)"
    if ! xcodebuild \
        -project "$PROJECT_NAME.xcodeproj" \
        -scheme "$SCHEME" \
        -configuration "$CONFIG" \
        -destination "generic/platform=iOS" \
        -derivedDataPath "$DERIVED_DATA" \
        -allowProvisioningUpdates \
        $team_arg \
        build 2>&1 | tee "$build_output" | tail -20; then
        if grep -qiE 'expired provisioning profile|profile has expired|invalid code signature|profile has not been explicitly trusted|0xe8008011|0x2712' "$build_output"; then
            show_signing_hint
        fi
        rm -f "$build_output"
        return 1
    fi
    rm -f "$build_output"

    echo "==> Build complete: $(app_path)"
}

cmd_install() {
    auto_detect_device
    echo "==> Installing on $DEVICE_UDID..."
    xcrun devicectl device install app \
        --device "$DEVICE_UDID" \
        "$(app_path)"
    echo "==> Installed."
}

cmd_launch() {
    auto_detect_device
    echo "==> Launching $BUNDLE_ID on $DEVICE_UDID..."
    local launch_output
    if ! launch_output=$(
        xcrun devicectl device process launch \
        --device "$DEVICE_UDID" \
        "$BUNDLE_ID" 2>&1
    ); then
        echo "$launch_output"
        if [[ "$launch_output" == *"invalid code signature"* || "$launch_output" == *"profile has not been explicitly trusted by the user"* ]]; then
            cat <<'EOF'
Hint: this is usually a device trust or signing issue.
1. On the iPhone, enable Developer Mode in Settings > Privacy & Security.
2. If the app or profile is untrusted, go to Settings > General > VPN & Device Management and trust the developer profile.
3. If the signing profile expired, open Xcode with Automatic Signing enabled and rebuild/deploy.
EOF
        fi
        return 1
    fi
    echo "$launch_output"
}

cmd_deploy() {
    cmd_build
    cmd_install
    cmd_launch
}

cmd_devices() {
    xcrun devicectl list devices
}

cmd_simulators() {
    xcrun simctl list devices available
}

simulator_udid_for_name() {
    local name="$1"
    xcrun simctl list devices available 2>/dev/null | awk -v target="$name" '
        $0 ~ "^[[:space:]]*" target " \\([0-9A-F-]+\\) \\((Booted|Shutdown)\\)" {
            line = $0
            sub("^[[:space:]]*" target " \\(", "", line)
            sub("\\) \\((Booted|Shutdown)\\).*$", "", line)
            print line
            exit
        }
    '
}

test_destination() {
    if [[ -n "$TEST_DESTINATION" ]]; then
        echo "$TEST_DESTINATION"
        return
    fi

    if [[ -n "$SIMULATOR_UDID" ]]; then
        echo "platform=iOS Simulator,id=$SIMULATOR_UDID"
        return
    fi

    local names=(
        "$SIMULATOR_NAME"
        "iPhone 17"
        "iPhone 13 Pro Max"
        "iPhone 16e"
        "iPhone 17 Pro"
        "iPhone 17 Pro Max"
    )

    local name
    for name in "${names[@]}"; do
        local udid
        udid="$(simulator_udid_for_name "$name")"
        if [[ -n "$udid" ]]; then
            echo "platform=iOS Simulator,id=$udid"
            return
        fi
    done

    cat >&2 <<EOF
No preferred iOS Simulator is available.
Set SIMULATOR_NAME, SIMULATOR_UDID, or TEST_DESTINATION, or install one of:
  ${names[*]}

Available simulators:
EOF
    cmd_simulators >&2
    exit 1
}

show_simulator_hint() {
    cat <<'EOF'
Hint: this looks like a transient Simulator launch/preflight issue.
1. Retry with the stable default: SIMULATOR_NAME="iPhone 17" ./build.sh test
2. If the Simulator is stuck busy, reset runtime state with: xcrun simctl shutdown all
3. To pin a known device, run ./build.sh simulators and then SIMULATOR_UDID=<UDID> ./build.sh test
EOF
}

cmd_test() {
    if [[ ! -d "$PROJECT_NAME.xcodeproj" ]]; then
        cmd_generate
    fi
    local destination
    destination="$(test_destination)"

    echo "==> Running tests on $destination..."
    export APP_VERSION=$(cat VERSION)
    local test_output
    test_output="$(mktemp)"
    if ! xcodebuild test \
        -project "$PROJECT_NAME.xcodeproj" \
        -scheme "$SCHEME" \
        -destination "$destination" \
        -derivedDataPath "$DERIVED_DATA" 2>&1 | tee "$test_output"; then
        if grep -qiE 'busy|failed preflight checks|FBSOpenApplicationServiceErrorDomain|Simulator device failed to launch' "$test_output"; then
            show_simulator_hint
        fi
        rm -f "$test_output"
        return 1
    fi
    rm -f "$test_output"
    echo "==> Tests complete."
}

case "$COMMAND" in
    generate) cmd_generate ;;
    build)    cmd_build ;;
    install)  cmd_install ;;
    launch)   cmd_launch ;;
    deploy)   cmd_deploy ;;
    test)     cmd_test ;;
    devices)  cmd_devices ;;
    simulators) cmd_simulators ;;
    *)        usage ;;
esac

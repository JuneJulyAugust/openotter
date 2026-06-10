#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

PROJECT_NAME="openotter"
SCHEME="$PROJECT_NAME"
CONFIG="${CONFIG:-Debug}"
DERIVED_DATA="$SCRIPT_DIR/.build/DerivedData"
BUNDLE_ID="${BUNDLE_ID:-com.openotter-ios.app}"
APP_VERSION="${APP_VERSION:-$(cat VERSION)}"

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
  DEVICE_UDID       CoreDevice or hardware device UDID (alternative to --device flag)
  XCODE_DEVICE_UDID Hardware device UDID for xcodebuild (auto-detected for deploy)
  CONFIG            Build configuration (default: Debug)
  BUNDLE_ID         Product bundle identifier (default: com.openotter-ios.app)
  APP_VERSION       Marketing version (default: contents of VERSION)
  SIMULATOR_NAME    Preferred test simulator name (default: iPhone 17)
  SIMULATOR_UDID    Exact test simulator UDID
  TEST_DESTINATION  Full xcodebuild test destination override
  ENABLE_CODE_COVERAGE  Set to 1 or YES to collect XCTest coverage
  RESULT_BUNDLE_PATH    Optional xcodebuild .xcresult path for tests
  CODE_SIGNING_ALLOWED  Optional xcodebuild override for simulator CI
  BUILD_DESTINATION     Optional xcodebuild destination override for device builds
  DEVELOPMENT_TEAM      Optional Apple Developer team override
  REINSTALL_ON_SIGNING_MISMATCH
                      Set to 0 to stop instead of uninstalling/retrying when
                      an installed app is signed by a different Apple team
EOF
    exit 1
}

# Parse global options
DEVICE_UDID="${DEVICE_UDID:-}"
XCODE_DEVICE_UDID="${XCODE_DEVICE_UDID:-}"
DEVICE_NAME="${DEVICE_NAME:-}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"
SIMULATOR_UDID="${SIMULATOR_UDID:-}"
TEST_DESTINATION="${TEST_DESTINATION:-}"
ENABLE_CODE_COVERAGE="${ENABLE_CODE_COVERAGE:-0}"
RESULT_BUNDLE_PATH="${RESULT_BUNDLE_PATH:-}"
CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-}"
BUILD_DESTINATION="${BUILD_DESTINATION:-}"
REINSTALL_ON_SIGNING_MISMATCH="${REINSTALL_ON_SIGNING_MISMATCH:-1}"
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
    local devices_json
    local devices_error
    devices_json="$(mktemp)"
    devices_error="$(mktemp)"
    if ! xcrun devicectl list devices \
        --filter "State BEGINSWITH 'available' OR State == 'connected'" \
        --timeout 30 \
        --json-output "$devices_json" \
        --quiet 2> "$devices_error"; then
        echo "Unable to query connected iOS devices via CoreDevice."
        cat "$devices_error"
        rm -f "$devices_json" "$devices_error"
        echo "Try reconnecting the iPhone, unlocking it, and running: xcrun devicectl list devices"
        exit 1
    fi
    rm -f "$devices_error"

    local -a core_ids=()
    local -a xcode_ids=()
    local -a names=()
    local index=0
    while true; do
        local core_id
        core_id="$(/usr/bin/plutil -extract "result.devices.$index.identifier" raw -o - "$devices_json" 2>/dev/null || true)"
        if [[ ! "$core_id" =~ ^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$ ]]; then
            break
        fi

        local xcode_id
        local name
        xcode_id="$(/usr/bin/plutil -extract "result.devices.$index.hardwareProperties.udid" raw -o - "$devices_json" 2>/dev/null || true)"
        name="$(/usr/bin/plutil -extract "result.devices.$index.deviceProperties.name" raw -o - "$devices_json" 2>/dev/null || echo "Unknown")"

        core_ids+=("$core_id")
        xcode_ids+=("$xcode_id")
        names+=("$name")
        index=$((index + 1))
    done
    rm -f "$devices_json"

    local count="${#core_ids[@]}"
    local selected=-1
    local requested="${DEVICE_UDID:-$XCODE_DEVICE_UDID}"

    if [[ -n "$requested" ]]; then
        local i
        for ((i = 0; i < count; i++)); do
            if [[ "$requested" == "${core_ids[$i]}" || "$requested" == "${xcode_ids[$i]}" ]]; then
                selected="$i"
                break
            fi
        done
        if [[ "$selected" -lt 0 ]]; then
            echo "Specified iOS device is not available: $requested"
            echo
            echo "Available devices:"
            for ((i = 0; i < count; i++)); do
                printf '  %s  CoreDevice=%s  Xcode=%s\n' "${names[$i]}" "${core_ids[$i]}" "${xcode_ids[$i]}"
            done
            exit 1
        fi
    elif [[ "$count" -eq 1 ]]; then
        selected=0
    elif [[ "$count" -gt 1 ]]; then
        echo "Multiple devices found. Specify with --device <UDID>:"
        local i
        for ((i = 0; i < count; i++)); do
            printf '  %s  CoreDevice=%s  Xcode=%s\n' "${names[$i]}" "${core_ids[$i]}" "${xcode_ids[$i]}"
        done
        exit 1
    else
        echo "No available iOS devices found."
        echo
        echo "CoreDevice currently reports:"
        xcrun devicectl list devices --timeout 30 || true
        cat <<'EOF'

If your iPhone is listed as unavailable, reconnect it, unlock it, confirm
"Trust This Computer" on the device, and make sure Developer Mode is enabled.
Then rerun:
  xcrun devicectl list devices
EOF
        exit 1
    fi

    DEVICE_UDID="${core_ids[$selected]}"
    XCODE_DEVICE_UDID="${xcode_ids[$selected]}"
    DEVICE_NAME="${names[$selected]}"
    echo "Auto-detected device: $DEVICE_NAME (CoreDevice $DEVICE_UDID, Xcode $XCODE_DEVICE_UDID)"
}

app_path() {
    echo "$DERIVED_DATA/Build/Products/$CONFIG-iphoneos/$PROJECT_NAME.app"
}

app_bundle_id() {
    local plist
    plist="$(app_path)/Info.plist"
    if [[ -f "$plist" ]]; then
        /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null \
            || echo "$BUNDLE_ID"
    else
        echo "$BUNDLE_ID"
    fi
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
    export APP_VERSION
    xcodegen generate
    echo "==> Done: $PROJECT_NAME.xcodeproj"
}

ensure_project() {
    cmd_generate
}

build_destination() {
    if [[ -n "$BUILD_DESTINATION" ]]; then
        echo "$BUILD_DESTINATION"
    elif [[ -n "$XCODE_DEVICE_UDID" ]]; then
        echo "id=$XCODE_DEVICE_UDID"
    elif [[ -n "$DEVICE_UDID" ]]; then
        echo "id=$DEVICE_UDID"
    else
        echo "generic/platform=iOS"
    fi
}

is_device_destination() {
    [[ -n "$XCODE_DEVICE_UDID" || -n "$DEVICE_UDID" || "$BUILD_DESTINATION" == id=* || "$BUILD_DESTINATION" == *",id="* ]]
}

cmd_build() {
    if [[ -n "$DEVICE_UDID" && -z "$XCODE_DEVICE_UDID" ]]; then
        auto_detect_device
    fi
    ensure_project

    local destination
    destination="$(build_destination)"

    local xcodebuild_args=(
        -project "$PROJECT_NAME.xcodeproj"
        -scheme "$SCHEME"
        -configuration "$CONFIG"
        -destination "$destination"
        -destination-timeout 30
        -derivedDataPath "$DERIVED_DATA"
        -allowProvisioningUpdates
    )
    if is_device_destination; then
        xcodebuild_args+=(-allowProvisioningDeviceRegistration)
    fi
    xcodebuild_args+=(
        PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID"
        MARKETING_VERSION="$APP_VERSION"
    )
    if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
        xcodebuild_args+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
    fi
    xcodebuild_args+=(build)

    echo "==> Building $SCHEME ($CONFIG) for $destination..."
    local build_output
    build_output="$(mktemp)"
    if ! xcodebuild "${xcodebuild_args[@]}" 2>&1 | tee "$build_output" | tail -20; then
        if grep -qiE 'expired provisioning profile|profile has expired|invalid code signature|profile has not been explicitly trusted|no devices from which to generate a provisioning profile|No profiles for|0xe8008011|0x2712' "$build_output"; then
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
    local bundle_id
    bundle_id="$(app_bundle_id)"
    echo "==> Installing on $DEVICE_UDID..."
    local install_output
    install_output="$(mktemp)"
    if xcrun devicectl device install app \
        --device "$DEVICE_UDID" \
        "$(app_path)" 2>&1 | tee "$install_output"; then
        rm -f "$install_output"
        echo "==> Installed."
        return 0
    fi

    if grep -qiE 'MismatchedApplicationIdentifierEntitlement|application-identifier entitlement string' "$install_output"; then
        if [[ "$REINSTALL_ON_SIGNING_MISMATCH" != "1" && "$REINSTALL_ON_SIGNING_MISMATCH" != "YES" ]]; then
            rm -f "$install_output"
            cat <<EOF
Hint: the installed app is signed by a different Apple team.
Delete OpenOtter from the iPhone, or rerun with:
  REINSTALL_ON_SIGNING_MISMATCH=1 ./build.sh --release deploy
EOF
            return 1
        fi

        echo "==> Installed app was signed by a different Apple team; uninstalling $bundle_id and retrying..."
        xcrun devicectl device uninstall app \
            --device "$DEVICE_UDID" \
            "$bundle_id"

        if xcrun devicectl device install app \
            --device "$DEVICE_UDID" \
            "$(app_path)"; then
            rm -f "$install_output"
            echo "==> Installed."
            return 0
        fi
    fi

    rm -f "$install_output"
    return 1
}

cmd_launch() {
    auto_detect_device
    local bundle_id
    bundle_id="$(app_bundle_id)"
    echo "==> Launching $bundle_id on $DEVICE_UDID..."
    local launch_output
    if ! launch_output=$(
        xcrun devicectl device process launch \
        --device "$DEVICE_UDID" \
        "$bundle_id" 2>&1
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
    auto_detect_device
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
    ensure_project
    local destination
    destination="$(test_destination)"

    echo "==> Running tests on $destination..."
    export APP_VERSION
    local xcodebuild_args=(
        test
        -project "$PROJECT_NAME.xcodeproj"
        -scheme "$SCHEME"
        -destination "$destination"
        -derivedDataPath "$DERIVED_DATA"
    )

    if [[ "$ENABLE_CODE_COVERAGE" == "1" || "$ENABLE_CODE_COVERAGE" == "YES" ]]; then
        xcodebuild_args+=(-enableCodeCoverage YES)
    fi

    if [[ -n "$RESULT_BUNDLE_PATH" ]]; then
        rm -rf "$RESULT_BUNDLE_PATH"
        mkdir -p "$(dirname "$RESULT_BUNDLE_PATH")"
        xcodebuild_args+=(-resultBundlePath "$RESULT_BUNDLE_PATH")
    fi

    xcodebuild_args+=(
        PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID"
        MARKETING_VERSION="$APP_VERSION"
    )
    if [[ -n "$CODE_SIGNING_ALLOWED" ]]; then
        xcodebuild_args+=(CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED")
    fi

    local test_output
    test_output="$(mktemp)"
    local attempt=1
    local max_attempts=2
    while true; do
        if [[ -n "$RESULT_BUNDLE_PATH" ]]; then
            rm -rf "$RESULT_BUNDLE_PATH"
            mkdir -p "$(dirname "$RESULT_BUNDLE_PATH")"
        fi
        : > "$test_output"

        if xcodebuild "${xcodebuild_args[@]}" 2>&1 | tee "$test_output"; then
            rm -f "$test_output"
            echo "==> Tests complete."
            return 0
        fi

        if grep -qiE 'busy|failed preflight checks|FBSOpenApplicationServiceErrorDomain|Simulator device failed to launch' "$test_output"; then
            show_simulator_hint
            if [[ "$attempt" -lt "$max_attempts" ]]; then
                echo "==> Simulator was busy; shutting down simulators and retrying once..."
                xcrun simctl shutdown all 2>/dev/null || true
                sleep 3
                attempt=$((attempt + 1))
                continue
            fi
        fi
        rm -f "$test_output"
        return 1
    done
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

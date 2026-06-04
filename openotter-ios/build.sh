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
  DEVICE_UDID       Device UDID (alternative to --device flag)
  CONFIG            Build configuration (default: Debug)
  BUNDLE_ID         Product bundle identifier (default: com.openotter-ios.app)
  APP_VERSION       Marketing version (default: contents of VERSION)
  SIMULATOR_NAME    Preferred test simulator name (default: iPhone 17)
  SIMULATOR_UDID    Exact test simulator UDID
  TEST_DESTINATION  Full xcodebuild test destination override
  ENABLE_CODE_COVERAGE  Set to 1 or YES to collect XCTest coverage
  RESULT_BUNDLE_PATH    Optional xcodebuild .xcresult path for tests
  CODE_SIGNING_ALLOWED  Optional xcodebuild override for simulator CI
EOF
    exit 1
}

# Parse global options
DEVICE_UDID="${DEVICE_UDID:-}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"
SIMULATOR_UDID="${SIMULATOR_UDID:-}"
TEST_DESTINATION="${TEST_DESTINATION:-}"
ENABLE_CODE_COVERAGE="${ENABLE_CODE_COVERAGE:-0}"
RESULT_BUNDLE_PATH="${RESULT_BUNDLE_PATH:-}"
CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-}"
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
    local devices_output
    if ! devices_output=$(xcrun devicectl list devices --timeout 30 2>&1); then
        echo "Unable to query connected iOS devices via CoreDevice."
        echo "$devices_output"
        echo "Try reconnecting the iPhone, unlocking it, and running: xcrun devicectl list devices"
        exit 1
    fi

    devices=$(printf '%s\n' "$devices_output" | awk '
        /[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/ &&
        /available|connected/ {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/) {
                    print $i
                }
            }
        }
    ' || true)
    local count
    if [[ -n "$devices" ]]; then
        count=$(printf '%s\n' "$devices" | wc -l | tr -d '[:space:]')
    else
        count=0
    fi

    if [[ "$count" -eq 1 ]]; then
        DEVICE_UDID="$(printf '%s\n' "$devices" | head -1 | xargs)"
        echo "Auto-detected device: $DEVICE_UDID"
    elif [[ "$count" -gt 1 ]]; then
        echo "Multiple devices found. Specify with --device <UDID>:"
        echo "$devices_output"
        exit 1
    else
        echo "No available iOS devices found."
        echo
        echo "CoreDevice currently reports:"
        echo "$devices_output"
        cat <<'EOF'

If your iPhone is listed as unavailable, reconnect it, unlock it, confirm
"Trust This Computer" on the device, and make sure Developer Mode is enabled.
Then rerun:
  xcrun devicectl list devices
EOF
        exit 1
    fi
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
        PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
        MARKETING_VERSION="$APP_VERSION" \
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

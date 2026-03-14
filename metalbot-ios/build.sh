#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

PROJECT_NAME="metalbot"
SCHEME="$PROJECT_NAME"
CONFIG="${CONFIG:-Debug}"
DERIVED_DATA="$SCRIPT_DIR/.build/DerivedData"
BUNDLE_ID="com.metalbot.app"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIG-iphoneos/$PROJECT_NAME.app"

usage() {
    cat <<EOF
Usage: $0 <command> [options]

Commands:
  generate    Generate Xcode project from project.yml (requires xcodegen)
  build       Build the iOS app
  install     Install app on connected device
  launch      Launch app on connected device
  deploy      Build + install + launch (full cycle)
  devices     List connected iOS devices

Options:
  --device <UDID>   Target device UDID (auto-detected if one device connected)
  --release         Use Release configuration

Environment:
  DEVICE_UDID       Device UDID (alternative to --device flag)
  CONFIG            Build configuration (default: Debug)
EOF
    exit 1
}

# Parse global options
DEVICE_UDID="${DEVICE_UDID:-}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --device) DEVICE_UDID="$2"; shift 2 ;;
        --release) CONFIG="Release"; shift ;;
        generate|build|install|launch|deploy|devices) COMMAND="$1"; shift; break ;;
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

cmd_generate() {
    echo "==> Generating Xcode project..."
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
    xcodebuild \
        -project "$PROJECT_NAME.xcodeproj" \
        -scheme "$SCHEME" \
        -configuration "$CONFIG" \
        -destination "generic/platform=iOS" \
        -derivedDataPath "$DERIVED_DATA" \
        -allowProvisioningUpdates \
        $team_arg \
        build 2>&1 | tail -20

    echo "==> Build complete: $APP_PATH"
}

cmd_install() {
    auto_detect_device
    echo "==> Installing on $DEVICE_UDID..."
    xcrun devicectl device install app \
        --device "$DEVICE_UDID" \
        "$APP_PATH"
    echo "==> Installed."
}

cmd_launch() {
    auto_detect_device
    echo "==> Launching $BUNDLE_ID on $DEVICE_UDID..."
    xcrun devicectl device process launch \
        --device "$DEVICE_UDID" \
        "$BUNDLE_ID"
}

cmd_deploy() {
    cmd_build
    cmd_install
    cmd_launch
}

cmd_devices() {
    xcrun devicectl list devices
}

case "$COMMAND" in
    generate) cmd_generate ;;
    build)    cmd_build ;;
    install)  cmd_install ;;
    launch)   cmd_launch ;;
    deploy)   cmd_deploy ;;
    devices)  cmd_devices ;;
    *)        usage ;;
esac

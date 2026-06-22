# openotter-ios

`openotter-ios` is the iPhone app for `openotter`. It handles LiDAR capture, RGB + point-cloud debug rendering, the Raspberry Pi WiFi bridge UI, the STM32 direct-control UI, and the Telegram-based agent runtime with TTS voice feedback.

## First-Time Setup

1. Install Xcode and the Xcode command line tools.
2. Install `xcodegen` if it is not already available:

   ```bash
   brew install xcodegen
   ```

3. Generate the Xcode project from `project.yml`:

   ```bash
   cd /Users/fxu/Projects/openotter/openotter-ios
   ./build.sh generate
   ```

4. Open `openotter.xcodeproj` in Xcode.
5. Select the `openotter` target, then open `Signing & Capabilities`.
6. Enable `Automatically manage signing` and select your Apple development team.
7. On the iPhone, enable `Developer Mode` in `Settings > Privacy & Security`.
8. After the first install, trust the developer profile in `Settings > General > VPN & Device Management` if iOS prompts for it.

## Daily Development

Use the build script from the `openotter-ios` directory:

```bash
./build.sh build
./build.sh install
./build.sh launch
./build.sh deploy
./build.sh test                 # Runs unit tests on the iOS Simulator
./build.sh --release deploy
```

If `./build.sh --release deploy` says the iPhone is `unavailable`, the Release
app was built but not installed. Unlock the phone, keep it awake, confirm the
Mac trust prompt if iOS shows one, reconnect USB if available, then rerun:

```bash
xcrun devicectl list devices
./build.sh --release deploy
```

During deploy, `build.sh` detects the iPhone before compiling and asks Xcode to
build for that device. This lets automatic signing create or refresh the local
development profile when the previous profile expires or the bundle ID changes.
If the Release build appears to pause at `codesign`, approve the macOS keychain
prompt for the Apple Development certificate.
If install reports a mismatched `application-identifier` entitlement, the script
removes the previously signed app and retries the install. Set
`REINSTALL_ON_SIGNING_MISMATCH=0` to stop instead of removing the old app.
After the first install from a newly selected Apple team, iOS may require
trusting that developer profile again in `Settings > General > VPN & Device Management`.

Do not use STM32 BLE screenshots from the phone until the latest app is
installed. The current STM32 Control debug box includes numbered BLE trace
entries such as `#12 scan...`; screenshots without numbered entries are from an
older app build.

### Worktree Mode

If the active feature branch lives in a git worktree while the repo root stays
on `main`, build from the worktree checkout, not the root checkout. For the
active SATEL-VL53L8 feature branch:

```bash
cd /Users/fang/projects/openotter/.worktrees/vl53l8-satel-firmware/openotter-ios
./build.sh generate
./build.sh test
```

That is the right place to run XcodeGen, Simulator tests, and any manual app
debugging while feature work is isolated in the worktree.

## If Signing Expires Again

If a future build fails with `expired provisioning profile`, `invalid code signature`, or `profile has not been explicitly trusted by the user`:

1. Open Xcode with the `openotter` project.
2. Confirm `Automatically manage signing` is still enabled for the `openotter` target.
3. Confirm the correct `Team` is selected.
4. If Xcode reports certificate issues, go to `Xcode > Settings > Accounts > Manage Certificates` and create a new Apple Development certificate.
5. Delete the app from the iPhone if a stale copy is still installed.
6. Make sure `Developer Mode` is enabled on the iPhone.
7. Trust the developer profile again in `Settings > General > VPN & Device Management` if iOS asks for it.
8. Re-run `./build.sh --release deploy`.

The project is already configured for automatic signing in `project.yml`, so the normal fix is to refresh the local Xcode signing state and rebuild. Apple development profiles are not permanent.

## Bumping the App Version

The app version is defined in a single source of truth: `openotter-ios/VERSION`.

To bump the version:
1. Edit the `openotter-ios/VERSION` file.
2. Run `./build.sh generate` to refresh the Xcode project when project settings changed.
3. The UI automatically reads the current version from the `Bundle` at runtime.

`build.sh build`, `build.sh deploy`, and `build.sh test` also pass
`MARKETING_VERSION` from `VERSION` into `xcodebuild`, so a stale generated
project cannot accidentally deploy the previous app version.

## Notes

- `project.yml` is the source of truth for signing and build settings.
- `build.sh` regenerates the Xcode project from `project.yml` before CLI builds, tests, and deploys.
- The STM32 direct-control screen uses reconnect-safe BLE scanning against the STM32 BLE peripheral `OPENOTTER-MCP`.
- If launch still fails after install, the script prints a trust/signing hint in the terminal.

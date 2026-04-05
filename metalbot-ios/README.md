# metalbot-ios

`metalbot-ios` is the iPhone app for `metalbot`. It handles LiDAR capture, RGB + point-cloud debug rendering, the Raspberry Pi WiFi bridge UI, the STM32 direct-control UI, and the Telegram-based agent runtime with TTS voice feedback.

## First-Time Setup

1. Install Xcode and the Xcode command line tools.
2. Install `xcodegen` if it is not already available:

   ```bash
   brew install xcodegen
   ```

3. Generate the Xcode project from `project.yml`:

   ```bash
   cd /Users/fxu/Projects/metalbot/metalbot-ios
   ./build.sh generate
   ```

4. Open `metalbot.xcodeproj` in Xcode.
5. Select the `metalbot` target, then open `Signing & Capabilities`.
6. Enable `Automatically manage signing` and select your Apple development team.
7. On the iPhone, enable `Developer Mode` in `Settings > Privacy & Security`.
8. After the first install, trust the developer profile in `Settings > General > VPN & Device Management` if iOS prompts for it.

## Daily Development

Use the build script from the `metalbot-ios` directory:

```bash
./build.sh build
./build.sh install
./build.sh launch
./build.sh deploy
./build.sh test                 # Runs unit tests on the iOS Simulator
./build.sh --release deploy
```

## If Signing Expires Again

If a future build fails with `expired provisioning profile`, `invalid code signature`, or `profile has not been explicitly trusted by the user`:

1. Open Xcode with the `metalbot` project.
2. Confirm `Automatically manage signing` is still enabled for the `metalbot` target.
3. Confirm the correct `Team` is selected.
4. If Xcode reports certificate issues, go to `Xcode > Settings > Accounts > Manage Certificates` and create a new Apple Development certificate.
5. Delete the app from the iPhone if a stale copy is still installed.
6. Make sure `Developer Mode` is enabled on the iPhone.
7. Trust the developer profile again in `Settings > General > VPN & Device Management` if iOS asks for it.
8. Re-run `./build.sh --release deploy`.

The project is already configured for automatic signing in `project.yml`, so the normal fix is to refresh the local Xcode signing state and rebuild. Apple development profiles are not permanent.

## Bumping the App Version

The app version is defined in a single source of truth: `metalbot-ios/VERSION`.

To bump the version:
1. Edit the `metalbot-ios/VERSION` file.
2. Run `./build.sh generate` to inject the new version into the Xcode project (`project.yml` sets `MARKETING_VERSION: ${APP_VERSION}`).
3. The UI automatically reads the current version from the `Bundle` at runtime.

## Notes

- `project.yml` is the source of truth for signing and build settings.
- `build.sh` runs `xcodegen generate`, builds, installs, and launches the app.
- The STM32 direct-control screen uses reconnect-safe BLE scanning against the STM32 BLE peripheral `METALBOT-MCP`.
- If launch still fails after install, the script prints a trust/signing hint in the terminal.

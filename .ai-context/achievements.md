# metalbot Achievement Index

This file tracks concrete task outcomes and their supporting artifacts.

## Storage Conventions

- Task evidence artifacts: `assets/achievements/<milestone>/YYYY-MM-DD_<slug>.png` or the relevant source/doc path when no screenshot exists.
- Design/source art assets: `assets/design/<platform-or-domain>/...`
- Walkthrough entries should reference files from this index.

## Achievements

| Date | Task | Outcome | Evidence |
| --- | --- | --- | --- |
| 2026-03-14 | MVP1 `1.1.1` + `1.1.2` | iOS app bring-up + LiDAR point-cloud capture and RGB debug display completed | `assets/achievements/mvp1/2026-03-14_lidar-pointcloud-rgb-capture-display.png` |
| 2026-03-19 | MVP1 `1.4.1` + `1.4.2` | Bi-directional MCP bridge (RPi + iOS) with 1.5s timeout and bi-directional TUI dashboard | `metalbot-ios/CHANGELOG.md` `0.2.0`; `metalbot-mcp/CHANGELOG.md` `0.1.0` |
| 2026-03-20 | MVP1 control path milestone | USB serial bridge, ACK logging, and Arduino actuation firmware for end-to-end control | `metalbot-ios/CHANGELOG.md` `0.3.0`; `metalbot-mcp/CHANGELOG.md` `0.2.0`; `firmware/metalbot-arduino/metalbot-arduino.ino` |

## App Branding Assets

- iOS app icon source: `assets/design/ios/app-icon/metalbot_icon_source.png`
- Compiled app icon target: `metalbot-ios/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`

# metalbot

<!-- markdownlint-disable MD033 -->
<img src="assets/design/ios/app-icon/metalbot_icon_source.png" alt="Metalbot app icon" width="128" />
<!-- markdownlint-enable MD033 -->

> iPhone-led autonomous RC platform with direct STM32 control

LiDAR, RGB, and VIO on the phone. BLE command handling, watchdog safety, and PWM actuation on the STM32L475 IoT board.

Metalbot is the public home for my autonomous RC car project. The active low-level controller is now an STM32L475 Discovery Kit IoT Node (`B-L475E-IOT01A`), which replaced the earlier Raspberry Pi + Arduino bridge. The architecture diagram is maintained in Draw.io and exported as a GitHub-friendly PNG. The iPhone handles perception, estimation, planning, and the operator UI, while the STM32 board drives steering and throttle directly. The name comes from Apple Metal, which matches the long-term plan to lean on GPU and compute paths on the iPhone.

![Metalbot system architecture](assets/design/metalbot-architecture.png)

## System Overview

| Layer | Responsibility | Notes |
| --- | --- | --- |
| iPhone app | LiDAR and RGB capture, VIO, planning, diagnostics, ESC telemetry | `metalbot-ios/README.md` |
| STM32 control board | BLE GATT command intake, watchdog, PWM actuation | `firmware/stm32-mcp/README.md` |
| Vehicle hardware | Steering servo, ESC, RC chassis | Direct PWM from the STM32 |

## Hardware

- iPhone 13 Pro or iPhone 13 Pro Max
- STM32L475 Discovery Kit IoT Node (`B-L475E-IOT01A`)
- RC chassis with steering servo and brushless ESC
- Flat indoor floor for MVP1
- Initial target speed range: `0.1` to `2.0` m/s

## Current Focus

- MVP1: LiDAR-first closed loop driving with ARKit `sceneDepth`, VIO, direct ESC telemetry, and STM32 PWM actuation
- MVP2: RGB-to-mono-depth prototype on iPhone
- MVP3: sparse LiDAR plus RGB depth completion

## Repository Map

### Active docs

- `metalbot-ios/README.md`: iPhone app setup, signing, and deploy flow
- `firmware/stm32-mcp/README.md`: STM32 BLE firmware, PWM control, and flashing
- `prototypes/esc_telemetry/README.md`: macOS ESC telemetry scanner and reverse-engineering tool
- `assets/README.md`: project assets and design sources
- `assets/design/metalbot-architecture.drawio`: editable system architecture diagram source

### Historical prototypes

- `metalbot-mcp/README.md`: archived Raspberry Pi bridge
- `firmware/learning-motor-ctrl/README.md`: archived Arduino motor-control prototype

## Build and Flash

- iPhone app: `cd metalbot-ios && ./build.sh deploy`
- STM32 firmware: `cd firmware/stm32-mcp && ./build.sh flash`

For deeper setup details, start with the component READMEs above.

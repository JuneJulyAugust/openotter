# OpenOtter

<!-- markdownlint-disable MD033 -->
<p align="center">
  <img src="assets/design/logos/light_title.png" alt="OpenOtter logo" width="400" />
</p>
<!-- markdownlint-enable MD033 -->

> Open-source physical AI platform for self-driving RC cars — accessible, fun, and educational for kids, makers, and RC fans of all skill levels

OpenOtter is an open-source educational platform for building autonomous RC cars with physical AI. Inspired by [comma.ai's openpilot](https://github.com/commaai/openpilot), we believe self-driving technology should be accessible to everyone — from curious kids to experienced makers.

The project started as **MetalBot**, an iPhone-first autonomous RC car using Apple's Metal GPU for perception and an STM32 microcontroller for motor actuation. It has since evolved into **OpenOtter**: a hardware-agnostic platform supporting multiple brains, chassis, and sensor configurations.

![OpenOtter system architecture](assets/design/openotter-architecture.png)

## What Makes OpenOtter Different

- **Hardware Flexible**: Use a smartphone (iOS/Android), Raspberry Pi, or NVIDIA Jetson Orin Nano Super as the brain. Pair with CSI cameras, ST Time-of-Flight sensors, or phone-native LiDAR.
- **Chassis Agnostic**: Works with various RC car chassis — not locked to one specific model.
- **Physical AI Agent**: Beyond just driving — OpenOtter features an on-device agent with memory, learning skills, and remote interaction via Telegram commands.
- **Robotic Claw Integration**: Framework for attaching a robotic claw so the rover can interact with its environment.
- **Education First**: Built to teach and inspire. Follow along on our YouTube channel.

## System Overview

| Layer | Responsibility | Notes |
| --- | --- | --- |
| Brain app | LiDAR and RGB capture, VIO, planning, diagnostics, ESC telemetry, agent runtime | `openotter-ios/README.md` |
| Agent runtime | Telegram bot, command interpretation, TTS voice feedback, skill/memory stubs | `openotter-ios/Sources/Agent/` |
| Motor Control Processor (MCP) | BLE GATT command intake, watchdog, PWM actuation | `firmware/stm32-mcp/README.md` |
| Vehicle hardware | Steering servo, ESC, RC chassis | Direct PWM from MCP |

## Supported Hardware

### Brains
- iPhone 13 Pro / Pro Max (LiDAR + ARKit)
- NVIDIA Jetson Orin Nano Super (planned)
- Android smartphones (planned)

### Motor Control Processors
- STM32L475 Discovery Kit IoT Node (`B-L475E-IOT01A`)
- Arduino Mega (legacy path via Raspberry Pi bridge)

### Chassis
- Any RC car with standard steering servo and brushless ESC
- Flat indoor floor for initial testing
- Target speed range: `0.1` to `2.0` m/s

## Current Focus

- **MVP1** (complete): LiDAR-first closed loop driving with ARKit, VIO, direct ESC telemetry, STM32 PWM actuation, and Telegram-based agent runtime with TTS voice feedback
- **MVP2**: RGB-to-mono-depth prototype on iPhone
- **MVP3**: Sparse LiDAR plus RGB depth completion
- **Long-term**: Physical AI agent with LLM intent parsing, skill subsystem, persistent memory, and robotic claw interaction

## Repository Map

### Active docs

- `openotter-ios/README.md`: iPhone app setup, signing, and deploy flow
- `firmware/stm32-mcp/README.md`: STM32 BLE firmware, PWM control, and flashing
- `prototypes/esc_telemetry/README.md`: macOS ESC telemetry scanner and reverse-engineering tool
- `assets/README.md`: Project assets and design sources
- `assets/design/openotter-architecture.drawio`: Editable system architecture diagram source

### Firmware

- `firmware/raspberry-pi-mcp/README.md`: Raspberry Pi WiFi bridge, UDP heartbeat, serial forwarding, and TUI dashboard
- `firmware/learning-motor-ctrl/README.md`: Archived Arduino motor-control prototype

## Build and Flash

- iPhone app: `cd openotter-ios && ./build.sh deploy`
- STM32 firmware: `cd firmware/stm32-mcp && ./build.sh flash`

For deeper setup details, start with the component READMEs above.

## Contributing

OpenOtter is open source and welcomes contributions. Whether you're adding support for new hardware, improving the AI agent, or fixing bugs — PRs are welcome.

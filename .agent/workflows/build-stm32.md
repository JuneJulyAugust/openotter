---
description: Build the STM32 firmware project (stm32-mcp) using STM32CubeCLT command line tools
---

# Build STM32 Firmware

## Prerequisites
- STM32CubeCLT installed at `/opt/st/STM32CubeCLT_1.21.0/`
- Project location: `firmware/stm32-mcp/`
- Target MCU: STM32L475 (Cortex-M4 with FPU)

## Steps

// turbo-all

1. Build the Debug firmware:
```bash
./build.sh build
```
Run from: `firmware/stm32-mcp/`

2. (Optional) Build Release firmware:
```bash
./build.sh -r build
```
Run from: `firmware/stm32-mcp/`

3. (Optional) Flash firmware to target via ST-Link:
```bash
./build.sh flash
```
Run from: `firmware/stm32-mcp/`

4. (Optional) Build and flash in one step:
```bash
./build.sh all
```
Run from: `firmware/stm32-mcp/`

5. (Optional) Clean build artifacts:
```bash
./build.sh clean
```
Run from: `firmware/stm32-mcp/`

## Script Reference

Run `./build.sh --help` for full usage, environment variable overrides, and examples.

# Arduino Mega 2560 Motor Control Exploration

Compile, flash, and control actuators on an Arduino Mega 2560 from a Linux host (Raspberry Pi, Jetson, etc.) using `arduino-cli`. Supports an MG995R steering servo, a 3650 3900KV brushless motor with 45A ESC, and a combined driving demo.

## Reorganized Structure

The exploration code is now organized into logical subdirectories:
- `sketches/`: Arduino `.ino` projects.
- `scripts/`: Control scripts to run/stop components.
- `tools/`: Environment setup and shared helpers.
- `drivers/`: Platform-specific drivers (e.g., CH341SER).

## Hardware

| Component | Pin | Notes |
|---|---|---|
| Arduino Mega 2560 | USB | Auto-detected `/dev/ttyUSB*` |
| Sensor Shield v2.0 | — | Stacked on Mega (ensure firm seating) |
| MG995R Servo (steering) | PWM Pin 4 | Front wheel angle: 50-130 degrees, neutral 90 |
| 3650 Brushless Motor | — | 3-phase wires to ESC motor leads |
| 45A ESC (motor) | PWM Pin 8 | Signal from Arduino; power from 2-3S LiPo via T-plug |

**Power notes:**
- **Connect the LiPo battery to the ESC before uploading motor sketches.** The ESC will not power up from USB alone.
- The servo can run from USB power for light loads. For sustained use, power the Sensor Shield externally.
- The ESC's BEC (5.8V/3A) can power the Arduino through the Sensor Shield servo rail if no USB is connected.

## Quick Start

1. **Setup Environment** (first run):
   ```bash
   source tools/setup_env.sh
   ```

2. **Run Scripts** (from the `scripts/` directory):
   ```bash
   cd scripts
   bash run_servo.sh          # sweep between 50-130 degrees
   bash run_motor.sh          # arm ESC, ramp forward/reverse 10%-40%
   bash run_combined.sh       # full driving demo
   ```

3. **Emergency Stop**:
   ```bash
   bash stop_motor.sh
   bash stop_servo.sh
   ```

4. **Serial Monitor**:
   ```bash
   bash monitor.sh            # live serial output from Arduino (Ctrl+C to exit)
   ```

## Project Structure

| Path | Description |
|---|---|
| `tools/common.sh` | Shared build/upload helpers |
| `tools/setup_env.sh` | Bootstrap arduino-cli and AVR toolchain |
| `scripts/monitor.sh` | Serial monitor (115200 baud) |
| `sketches/` | Arduino `.ino` project folders |
| `scripts/` | Shell scripts to compile/flash specific sketches |
| `.ai-context/` | Hardware specs and learning context |
| `tools/arduino-cli.yaml` | Compiler configuration |
| `tools/arduino_data/` | Local toolchain (git-ignored) |
| `images/` | Hardware wiring reference photos |

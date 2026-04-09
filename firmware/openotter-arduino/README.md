# OpenOtter Arduino Control

This module provides the low-level servo and motor control for the OpenOtter. It communicates with the Raspberry Pi (MCP) via USB Serial.

## Hardware Setup

- **Arduino Mega 2560** (or similar)
- **ESC (Motor):** Pin 8
- **Steering Servo:** Pin 4
- **Power:** 7.4V (2S LiPo) recommended for servos/motor.

## Protocol

The Arduino listens for newline-terminated strings on the Serial port (115200 baud):
`S:<float>,M:<float>\n`

- `S`: Steering (-1.0 to 1.0)
- `M`: Motor (-1.0 to 1.0)

Example: `S:0.50,M:0.20\n` (50% right, 20% forward)

## Safety Features

- **Arming:** On startup, the ESC requires a 3-second neutral signal to arm. The Arduino handles this automatically.
- **Heartbeat Timeout:** If no command is received for 2 seconds, the sketch logs a safety timeout. Neutralization is currently disabled for debugging, so the outputs are left unchanged until new commands arrive or the board resets.

## Deployment

Deploy the sketch to the Arduino connected to the Raspberry Pi:

```bash
./deploy.sh [pi-hostname]
```

## Manual Testing (from Pi)

You can send manual commands to test the servos:

```bash
echo "S:1.0,M:0.0" > /dev/ttyUSB0
echo "S:-1.0,M:0.0" > /dev/ttyUSB0
echo "S:0.0,M:0.1" > /dev/ttyUSB0
```

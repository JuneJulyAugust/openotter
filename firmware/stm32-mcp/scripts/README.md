# STM32 Firmware Scripts

Run these tools from the repository root or from `firmware/stm32-mcp`.

Use the project virtualenv when a script is Python-based:

```bash
/Users/fang/projects/openotter/.venv/bin/python firmware/stm32-mcp/scripts/read_uart.py --help
```

## `read_uart.py`

Live-read the IOT01A1 ST-LINK virtual COM port at 115200 baud.

Common commands:

```bash
# List detected ST-LINK serial ports.
/Users/fang/projects/openotter/.venv/bin/python firmware/stm32-mcp/scripts/read_uart.py --list

# Follow the first /dev/cu.usbmodem* port until Ctrl-C.
/Users/fang/projects/openotter/.venv/bin/python firmware/stm32-mcp/scripts/read_uart.py

# Capture a 45-second smoke-test log.
/Users/fang/projects/openotter/.venv/bin/python firmware/stm32-mcp/scripts/read_uart.py \
  --seconds 45 \
  --timestamp \
  --output /tmp/openotter-stm32-uart.log

# Use a specific port.
OPENOTTER_UART=/dev/cu.usbmodem112203 \
  /Users/fang/projects/openotter/.venv/bin/python firmware/stm32-mcp/scripts/read_uart.py
```

The script uses only Python standard-library `termios` and `select`; it does
not require `pyserial`.

When running inside a Codex sandbox, direct access to `/dev/cu.usbmodem*`
usually needs an escalated command approval. From a normal macOS terminal it can
run directly.

Expected healthy SATEL-VL53L8 SPI logs include lines like:

```text
VL53L8 rear selected transport=spi1
VL53L8 rear stream start layout=4 zones=16 hz=30
VL53L8 rear frame layout=4 zones=16 seq=... fps=30
LOOP iter=... tick=...
```

## Firmware Deploy Rule For Remote Sessions

Builds are normal workspace operations:

```bash
cd firmware/stm32-mcp
BUILD_TYPE=Release ./build.sh
```

Flashing and UART reading are host-device operations. Do not keep retrying
`./build.sh flash` inside a restricted sandbox after it fails with device or
probe errors. Use one of these paths instead:

1. Ask for approval to run the exact host-device command.
2. Have the user run the command from a normal terminal.
3. If SWD enumeration fails but `/Volumes/DIS_L4IOT` is mounted, copy the
   generated `.bin` to that volume:

   ```bash
   cp firmware/stm32-mcp/build/Release/stm32-mcp.bin /Volumes/DIS_L4IOT/stm32-mcp.bin
   ```

See `docs/dev/13-firmware-deploy-and-uart.md` for the full deployment playbook.

## `scan_stm32_ble.swift`

Use this macOS-only CoreBluetooth scanner when UART says the firmware is alive
but iOS remains in `Scanning`. It answers one focused question: can the Mac see
the STM32 advertisement over the air?

```bash
swift firmware/stm32-mcp/scripts/scan_stm32_ble.swift --seconds 20
```

Healthy output contains a starred `OPENOTTER-MCP` line with FE40/FE60 service
UUIDs:

```text
* adv id=2D5EB700 name=OPENOTTER-MCP local=OPENOTTER-MCP rssi=-58 svc=FE40,FE60 ...
```

If UART shows `BLE adv_active` but this scanner never prints `OPENOTTER-MCP`,
wait for `BLE adv_refresh stop ok` / `BLE adv_reassert ok` and scan again. If
the Mac sees `OPENOTTER-MCP` but iOS still scans, focus on the iOS scanner trace
instead of the firmware main loop.

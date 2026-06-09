# 13 - Firmware Deploy And UART Log Playbook

This page is the rulebook for firmware update and serial-log sessions. It
exists because building firmware, flashing firmware, and reading UART logs have
different host permissions.

## Golden Rule

Build from inside the worktree. Flash and serial-read on the host. For a
hardware-validation loop, run the whole build + flash + UART sequence with host
approval up front so the build artifacts, ST-LINK volume, and serial port are
all visible to the same macOS session.

In a Codex or other sandboxed session:

- a pure compile with `./build.sh` is usually fine in the workspace sandbox;
- a hardware-validation build should be escalated up front because the next
  steps need host USB/filesystem access anyway;
- reading `/dev/cu.usbmodem*` usually needs host-device approval;
- writing to `/Volumes/DIS_L4IOT` usually needs host-filesystem approval;
- `./build.sh flash` may fail even when the board is present because SWD probe
  enumeration is different from ST-LINK serial enumeration;
- do not keep retrying a failed flash command without changing the path. Switch
  to the mass-storage flash fallback or ask the user to run the host command.

## Build

Debug build:

```bash
cd /Users/fang/projects/openotter/.worktrees/vl53l8-satel-firmware/firmware/stm32-mcp
./build.sh
```

Release build:

```bash
cd /Users/fang/projects/openotter/.worktrees/vl53l8-satel-firmware/firmware/stm32-mcp
BUILD_TYPE=Release ./build.sh
```

The generated images are:

```text
build/Debug/stm32-mcp.elf
build/Debug/stm32-mcp.bin
build/Release/stm32-mcp.elf
build/Release/stm32-mcp.bin
```

## Preferred Flash Paths

### Path A: ST-LINK Mass Storage

Use this when `/Volumes/DIS_L4IOT` is mounted. It was the reliable path during
the 2026-06-08 remote session when CubeProgrammer could see the serial port but
not the SWD debug probe.

```bash
cd /Users/fang/projects/openotter/.worktrees/vl53l8-satel-firmware/firmware/stm32-mcp
BUILD_TYPE=Release ./build.sh
cp build/Release/stm32-mcp.bin /Volumes/DIS_L4IOT/stm32-mcp.bin
```

After the copy, the ST-LINK loader programs the target. The volume may briefly
disconnect/reconnect. Reopen UART and confirm the boot log.

From Codex, the `cp ... /Volumes/DIS_L4IOT/...` step requires escalation because
it writes outside the workspace. Ask once with a narrow command; do not work
around the sandbox.

### Path B: CubeProgrammer SWD

Use this only when CubeProgrammer can list the ST-LINK debug probe.

```bash
arch -x86_64 /opt/ST/STM32CubeCLT_1.21.0/STM32CubeProgrammer/bin/STM32_Programmer_CLI \
  --list
```

If it lists an ST-LINK, flash:

```bash
cd /Users/fang/projects/openotter/.worktrees/vl53l8-satel-firmware/firmware/stm32-mcp
arch -x86_64 /opt/ST/STM32CubeCLT_1.21.0/STM32CubeProgrammer/bin/STM32_Programmer_CLI \
  --connect port=SWD reset=SWrst \
  --download build/Release/stm32-mcp.elf \
  --verify \
  --go
```

On Apple Silicon, forcing `arch -x86_64` avoids the observed Qt/NEON loader
failure:

```text
Incompatible processor. This Qt build requires the following features:
    neon
```

If `--list` shows the VCP UART but says `No ST-Link detected!`, do not keep
retrying SWD. Use Path A or reconnect the USB cable/hub.

## Live UART Logs

Use the reusable reader:

```bash
/Users/fang/projects/openotter/.venv/bin/python \
  /Users/fang/projects/openotter/.worktrees/vl53l8-satel-firmware/firmware/stm32-mcp/scripts/read_uart.py
```

List detected ports:

```bash
/Users/fang/projects/openotter/.venv/bin/python \
  firmware/stm32-mcp/scripts/read_uart.py --list
```

Capture a bounded smoke test:

```bash
/Users/fang/projects/openotter/.venv/bin/python \
  firmware/stm32-mcp/scripts/read_uart.py \
  --seconds 45 \
  --timestamp \
  --output /tmp/openotter-stm32-uart.log
```

Use a specific port:

```bash
OPENOTTER_UART=/dev/cu.usbmodem112203 \
  /Users/fang/projects/openotter/.venv/bin/python \
  firmware/stm32-mcp/scripts/read_uart.py
```

Expected healthy v1.2.0 rear SATEL SPI log:

```text
BOOT phase=services_ready
BLE adv_start ok
BLE adv_active tick=...
BLE adv_refresh stop ok tick=...
BLE adv_reassert ok tick=...
VL53L8 rear probe transport=i2c3 ... alive=0
VL53L8 rear probe transport=spi1 ... alive=1
VL53L8 rear selected transport=spi1
VL53L8 rear stream start layout=4 zones=16 hz=30
VL53L8 rear frame layout=4 zones=16 seq=... fps=30
LOOP iter=... tick=...
```

## Reset/Reconnect Smoke Test

After flashing, use this flow before a release tag:

1. Open the iOS STM32 Control debug view.
2. Confirm STM32 Control connects.
3. Confirm Rear depth map renders FE62 frames.
4. Reset or power-cycle the STM32 board.
5. Keep the iOS view open during the reset.
6. Watch UART:

   ```text
   BLE connect handle=...
   BLE mode_write prev=0 new=1
   L8 dbg: ...
   VL53L8 rear frame layout=4 zones=16 ...
   ```

7. If iOS shows FE63 online/running but no FE62 frames, press the visible
   reconnect button in STM32 Control. The app should replay FE44 Debug and FE61
   config.
8. If iOS stays in `Scanning`, check whether UART still prints
   `BLE adv_active tick=...` and VL53L8 frame/debug logs. That proves the
   firmware main loop and sensor are alive, but it does not prove the
   advertisement is visible over the air. Wait for `BLE adv_refresh stop ok`
   plus `BLE adv_reassert ok`, then press refresh in STM32 Control and inspect
   the rolling BLE trace for `matched advertisement`, `connecting`, or only
   unrelated advertisements.
9. If UART shows `PANIC:C`, the firmware detected a wedged BlueNRG HCI command
   path and rebooted through the neutral-safe panic path. Confirm it comes back
   advertising and streams frames after reconnect.

For a second opinion on RF visibility, run a Mac BLE scan from a normal
terminal or an approved host command. Seeing `OPENOTTER-MCP` with FE40/FE60
service UUIDs means the STM32 is advertising and the remaining issue is iOS
discovery or connection state:

```bash
swift firmware/stm32-mcp/scripts/scan_stm32_ble.swift --seconds 20
```

## Troubleshooting Matrix

| Symptom | Action |
| --- | --- |
| `/dev/cu.usbmodem*` missing | Reconnect ST-LINK USB, check cable/hub, run `system_profiler SPUSBDataType`. |
| `read_uart.py` gets `Operation not permitted` in Codex | Rerun with an escalated command approval or use a normal terminal. |
| CubeProgrammer says `No debug probe detected` | Check `--list`. If only UART appears, use `/Volumes/DIS_L4IOT` mass-storage flashing. |
| CubeProgrammer exits with Qt/NEON error | Use the x86_64 slice: `arch -x86_64 .../STM32_Programmer_CLI`. |
| Mass-storage volume absent | Reconnect ST-LINK USB; some hubs expose VCP but not the disk. Use SWD only if `--list` sees ST-LINK. |
| UART shows `PANIC:C` | BlueNRG HCI timed out during stale BLE recovery. Let the board reboot and reconnect the app. |
| UART shows rear frames but iOS waits forever | FE63 status is alive but FE62 Debug stream did not start. Reconnect STM32 Control and confirm FE44/FE61 are replayed. |
| UART shows `BLE adv_active` but iOS remains `Scanning` | Firmware is alive and believes advertising is active, but this is not proof of RF visibility. Wait for `BLE adv_refresh stop ok` / `BLE adv_reassert ok`; if a Mac BLE scan sees `OPENOTTER-MCP` FE40/FE60, treat the remaining issue as app-side discovery and read the STM32 Control BLE trace. |

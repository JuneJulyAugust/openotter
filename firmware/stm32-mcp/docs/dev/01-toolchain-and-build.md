# 01 — Toolchain Setup and Build

This document covers everything needed to go from a freshly installed macOS
development machine to a flashed `stm32-mcp` firmware image running on the
**B-L475E-IOT01A** Discovery Kit.

All commands in this document are run from the project root unless otherwise
stated. Absolute paths referenced below:

| Name               | Path                                                  |
|--------------------|-------------------------------------------------------|
| Project root       | `firmware/stm32-mcp/`                                 |
| STM32CubeCLT root  | `/opt/ST/STM32CubeCLT_1.21.0/`                        |
| Build output       | `firmware/stm32-mcp/build/Debug/` (or `Release/`)     |
| ELF image          | `build/<cfg>/stm32-mcp.elf`                           |

If you are working in a git worktree, replace `firmware/stm32-mcp/` above
with the worktree path. For this feature branch that is:

`/Users/fang/projects/openotter/.worktrees/vl53l5cx-tof-debug/firmware/stm32-mcp/`

The commands below are the same after that path change.

---

## 1. What STM32CubeCLT provides

STM32CubeCLT is a single installer that bundles every host-side tool this
project needs:

| Tool                     | Purpose                              | Path (inside install root)               |
|--------------------------|--------------------------------------|------------------------------------------|
| `arm-none-eabi-gcc`      | Cross-compiler (C, ASM)              | `GNU-tools-for-STM32/bin/`               |
| `arm-none-eabi-objcopy`  | ELF → `.bin`/`.hex` conversion       | `GNU-tools-for-STM32/bin/`               |
| `arm-none-eabi-size`     | Report FLASH/RAM usage               | `GNU-tools-for-STM32/bin/`               |
| `cmake`                  | Build system generator               | `CMake/bin/`                             |
| `ninja`                  | Build driver (fast, parallel)        | `Ninja/bin/`                             |
| `STM32_Programmer_CLI`   | ST-Link flash/erase/mass-verify tool | `STM32CubeProgrammer/bin/`               |

Installing anything else (Homebrew `arm-none-eabi-gcc`, system `cmake`,
system `ninja`) is **not required** and may cause version drift. The
`build.sh` script prepends the CubeCLT binaries to `PATH` so they are
always used in preference to whatever the host shell would otherwise pick.

---

## 2. Installing STM32CubeCLT on macOS

1. Download the macOS build from
   <https://www.st.com/en/development-tools/stm32cubeclt.html>.
2. Run the `.pkg` installer. The default install destination on the new
   Macs is `/opt/ST/STM32CubeCLT_<version>/` (Apple Silicon and Intel).
3. Verify the expected layout after installation:

   ```bash
   ls /opt/ST/STM32CubeCLT_1.21.0
   # Expected top-level entries:
   # CMake/  GNU-tools-for-STM32/  Ninja/  STM32CubeProgrammer/  ...
   ```

4. (Optional) Sanity-check each tool is executable and reports its version:

   ```bash
   /opt/ST/STM32CubeCLT_1.21.0/GNU-tools-for-STM32/bin/arm-none-eabi-gcc --version
   /opt/ST/STM32CubeCLT_1.21.0/CMake/bin/cmake --version
   /opt/ST/STM32CubeCLT_1.21.0/Ninja/bin/ninja --version
   /opt/ST/STM32CubeCLT_1.21.0/STM32CubeProgrammer/bin/STM32_Programmer_CLI --version
   ```

No further step is required to compile the firmware — `build.sh` finds all
tools under this root. You do **not** need to edit `~/.zshrc` or export
`PATH` permanently.

> **Note:** ST's installers sometimes differ in path casing across versions
> (`/opt/st/...` vs `/opt/ST/...`). The `build.sh` default is
> `/opt/st/STM32CubeCLT_1.21.0`. If yours is installed to a different path
> (for example the uppercase `ST`), export `CUBECLT_ROOT` before running
> the script — see section 4 below.

### 2.1 PATH — what, if anything, to add

You only need to modify `PATH` in two situations:

1. You want to run `arm-none-eabi-gdb`, `cmake`, or the programmer CLI
   directly from your shell (outside `build.sh`).
2. You want editor/IDE tooling (clangd, VS Code CMake extension, etc.) to
   pick up the cross-compiler automatically.

In those cases add the following to `~/.zshrc` (or `~/.zprofile`):

```bash
export CUBECLT_ROOT="/opt/ST/STM32CubeCLT_1.21.0"
export PATH="$CUBECLT_ROOT/GNU-tools-for-STM32/bin:$CUBECLT_ROOT/CMake/bin:$CUBECLT_ROOT/Ninja/bin:$CUBECLT_ROOT/STM32CubeProgrammer/bin:$PATH"
```

Then reload:

```bash
source ~/.zshrc
which arm-none-eabi-gcc   # should print a path under /opt/ST/STM32CubeCLT_...
```

For CI, or when multiple CubeCLT versions coexist, prefer exporting only
`CUBECLT_ROOT` and letting `build.sh` handle the rest.

### 2.2 USB / ST-Link driver

macOS does **not** require a kernel extension for the ST-Link; the
programmer CLI speaks USB directly via `libusb`. The first time you plug
the board in, macOS may briefly show a "New USB device" notification. You
do not need to install STSW-LINK009 on macOS.

If `STM32_Programmer_CLI` cannot see the probe you will get
`Error: No STLink device detected!`. Troubleshooting steps are in
`02-board-bringup.md`.

---

## 3. Build script (`build.sh`) cheat sheet

`build.sh` is a thin wrapper over `cmake`, `ninja`, `objcopy`, `size`, and
`STM32_Programmer_CLI`. The full argument reference is also available via
`./build.sh --help`.

### 3.1 Subcommands

| Command     | What it does                                                                 |
|-------------|------------------------------------------------------------------------------|
| *(none)* / `build` | `configure` → `build` → generate `.bin` / `.hex` → print size report |
| `configure` | Run `cmake --preset <Debug\|Release>` only                                   |
| `artifacts` | Generate `.bin` / `.hex` from an existing `.elf` without rebuilding          |
| `flash`     | Flash the latest `.elf` to the target via ST-Link/SWD, verify, run          |
| `all`       | Build then flash                                                             |
| `clean`     | Delete `build/<cfg>/`                                                        |

### 3.2 Options

| Option            | Effect                              |
|-------------------|-------------------------------------|
| `-r`, `--release` | Build with `-Os -g0` (default: `-O0 -g3`) |
| `-h`, `--help`    | Print usage                         |

### 3.3 Environment overrides

| Variable         | Default                              | Purpose                                 |
|------------------|--------------------------------------|-----------------------------------------|
| `CUBECLT_ROOT`   | `/opt/st/STM32CubeCLT_1.21.0`        | CubeCLT install path                    |
| `BUILD_TYPE`     | `Debug` (overridden by `-r`)         | `Debug` or `Release`                    |
| `STLINK_PORT`    | `SWD`                                | `SWD` or `JTAG`                         |
| `STLINK_RESET`   | `SWrst`                              | Reset strategy (`SWrst`, `HWrst`, ...) |

### 3.4 Typical workflows

```bash
cd firmware/stm32-mcp

# One-off: build Debug (first run of the day, or after a pull)
./build.sh

# Code iteration: incremental rebuild + flash + run on the board
./build.sh all

# Release image for field tests
./build.sh -r all

# Wipe the build dir (rarely needed; ninja handles incrementality well)
./build.sh clean

# Custom CubeCLT path (new Mac where it's installed under /opt/ST/)
CUBECLT_ROOT=/opt/ST/STM32CubeCLT_1.21.0 ./build.sh
```

### 3.5 Under-the-hood commands

For debugging the build itself, the exact commands `build.sh` runs are:

```bash
# 1. Configure
cmake --preset Debug -S firmware/stm32-mcp
# → generates build/Debug/build.ninja via CMakePresets.json

# 2. Compile + link
cmake --build --preset Debug
# → builds stm32-mcp.elf

# 3. Convert to raw binary and Intel HEX
arm-none-eabi-objcopy -O binary stm32-mcp.elf stm32-mcp.bin
arm-none-eabi-objcopy -O ihex   stm32-mcp.elf stm32-mcp.hex

# 4. Print FLASH/RAM usage
arm-none-eabi-size stm32-mcp.elf

# 5. Flash via ST-Link over SWD
STM32_Programmer_CLI \
    --connect port=SWD reset=SWrst \
    --download stm32-mcp.elf \
    --verify \
    --go
```

Re-run any of these by hand if you need finer control (for example,
flashing a HEX instead of an ELF, or using JTAG instead of SWD).

---

## 4. First build on a fresh machine — full sequence

Assuming a fresh clone of the repo and a fresh CubeCLT install at
`/opt/ST/STM32CubeCLT_1.21.0/`:

```bash
# 0. (Once) Ensure git-lfs so Drivers/ is populated
brew install git-lfs
git lfs install
cd /path/to/openotter
git lfs pull

# 1. Enter the firmware project
cd firmware/stm32-mcp

# 2. Point build.sh at the new install path
export CUBECLT_ROOT=/opt/ST/STM32CubeCLT_1.21.0

# 3. Configure and build Debug
./build.sh

# 4. Plug in the board and flash
./build.sh flash
```

A successful Debug build ends with output similar to:

```
   text    data     bss     dec     hex filename
  35836     116    4480   40432    9df0 build/Debug/stm32-mcp.elf
[OK]    Flash and verify complete.
```

---

## 5. Troubleshooting

| Symptom                                              | Likely cause / fix                                                                                        |
|------------------------------------------------------|-----------------------------------------------------------------------------------------------------------|
| `STM32CubeCLT not found at /opt/st/...`              | Case-mismatched install path. `export CUBECLT_ROOT=/opt/ST/STM32CubeCLT_1.21.0`.                           |
| `Required tool not found: .../ninja`                 | Incomplete CubeCLT install — re-run the `.pkg` installer with every component checked.                    |
| `cmake: command not found` outside `build.sh`        | Only `build.sh` prepends CubeCLT to `PATH`. Export it permanently (see section 2.1) or use `build.sh`.     |
| `No STLink device detected!`                         | See bringup doc `02-board-bringup.md`. Usually USB cable is a charge-only cable or probe firmware outdated.|
| Link error: `undefined reference to __stack_chk_...` | Old CubeCLT. Upgrade to ≥1.17.                                                                            |
| `FLASH overflow by ...`                              | Release build should be well under 1 MB. Rebuild clean and check `size` output.                          |
| Build succeeds but `aci_gatt_*` symbols missing      | `BLUENRG_MS=1` not defined — don't edit `cmake/stm32cubemx/CMakeLists.txt` by hand.                        |

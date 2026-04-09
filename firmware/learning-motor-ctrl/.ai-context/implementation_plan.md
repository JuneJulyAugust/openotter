# Arduino Mega 2560 Project

## Phase 1: Connect Arduino Mega 2560 to Jetson (Completed)
We successfully connected the Arduino Mega 2560 (CH340 chip) to the Jetson, compiled the `ch34x` driver from source, resolved a conflict with `brltty`, and achieved a stable serial connection on `/dev/ttyUSB0`.

### Completed Steps
1. Captured initial system state (disconnected)
2. Captured post-connection system state (connected)
3. Diffed to find exact device ID (1a86:7523 QinHeng Electronics CH340) and assigned TTY port
4. Identified the `ch341` kernel module was missing from the Jetson kernel.
5. Downloaded `CH341SER` source, compiled `ch34x.ko` via `make`, and installed it.
6. Removed `brltty` service which was claiming the USB interface and causing immediate disconnections.
7. Loaded the module via `modprobe ch34x` and verified the Arduino mounted stably at `/dev/ttyUSB0`.

## Phase 2: Servo Control Demo (Completed)
The goal is to write a demo program to control a servo motor connected to **pin 9** of the PWM section on the Sensor Shield.
We will use `arduino-cli` on the Jetson to compile and upload the sketch to the Arduino.

### Completed Steps
1. **Document Hardware**: Record the servo connection on the Sensor Shield (PWM Pin 9).
2. **Install Arduino CLI**: Download and install `arduino-cli` to manage libraries, compile, and upload code.
3. **Configure Board Environment**: Install the `arduino:avr` core so we can compile for the Mega 2560 framework.
4. **Write Sketch**: Create `servo_demo/servo_demo.ino` using the standard `Servo.h` library, attaching to pin 9 and sweeping the servo back and forth.
5. **Compile & Upload**: Compile the sketch and upload it via `/dev/ttyUSB0`.

## Phase 3: Control Scripts and Documentation (Completed)
The goal is to provide a clean, high-level mechanism to manage the Arduino and document the environment for future developers.

### Completed Steps
1. **Develop `setup_env.sh`**: A simple bash script to append the `arduino-cli` binary path to `$PATH`.
2. **Develop `servo_stop` Sketch**: Create a new Arduino script that attaches to the servo and instructs it to stop moving (e.g., hold a neutral 90-degree position or detach).
3. **Develop High-Level Bash Scripts**:
    - `run_servo.sh`: Wrapper to compile and flash `servo_demo.ino`.
    - `stop_servo.sh`: Wrapper to compile and flash `servo_stop.ino`.
4. **Create `README.md`**: Document the end-to-end setup, compile instructions, serial port configuration, and the location of downloaded Arduino tools and libraries (`~/.arduino15`).

## Phase 4: Localize Arduino Environment (Completed)
The goal was to decouple the project from the user's global `~/.arduino15` directory and store all Arduino toolchains, libraries, and board configurations directly within the `./tools/arduino_data` directory for better portability.

### Completed Steps
1. **Create Local Config**: Initialized `arduino-cli.yaml` in `tools/`.
2. **Update Data Paths**: Configured `arduino-cli.yaml` to point to `tools/arduino_data/`.
3. **Migrate/Install Files**: Set up `setup_env.sh` to populate `tools/arduino_data/` locally.
4. **Update Scripts/Docs**: Exported `ARDUINO_CONFIG_FILE` and `ARDUINO_DIRECTORIES_*` variables in `tools/common.sh` and `tools/setup_env.sh`.

## Phase 5: Project Organization and Robustness (Completed)
The goal was to ensure the repository remains lightweight and the scripts work reliably from any directory.

### Completed Steps
1. **Clean up git tracking**: Removed `bin/arduino-cli` and other heavy binaries from git.
2. **Add structural `.gitkeep`s**: Maintained directory structure in `bin/` and `arduino_data/`.
3. **Enhance `setup_env.sh`**: Automated the `arduino-cli` download and AVR toolchain/library installation.
4. **Absolute Path Resolution**: Updated `tools/common.sh` and all `scripts/*.sh` to use absolute paths (`$SKETCHES_DIR`, `$TOOLS_DIR`) for robustness, allowing scripts to be executed from any current working directory.

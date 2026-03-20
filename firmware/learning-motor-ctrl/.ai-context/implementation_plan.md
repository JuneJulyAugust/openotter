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

## Phase 4: Localize Arduino Environment (Pending)
The goal is to decouple the project from the user's global `~/.arduino15` directory and store all Arduino toolchains, libraries, and board configurations directly within the `./arduino_demo` repository for better portability.

### Proposed Steps
1. **Create Local Config**: Use `arduino-cli config init` to create a local `arduino-cli.yaml` in the project root.
2. **Update Data Paths**: Modify `arduino-cli.yaml` to set `directories.data`, `directories.downloads`, and `directories.user` to point to a new local folder (e.g., `./arduino_data`).
3. **Migrate Existing Files**: Move the existing contents of `~/.arduino15` into the new `./arduino_data` directory.
4. **Update Scripts/Docs**: Ensure `setup_env.sh`, `run_servo.sh`, and `stop_servo.sh` pass the `--config-file arduino-cli.yaml` parameter or export the `ARDUINO_CONFIG_FILE` variable. Update `README.md` and `.gitignore` so we don't commit megabytes of toolchain binaries.
5. **Clean up**: Remove the now-unused `~/.arduino15` directory.

## Phase 5: Project Organization and Bootstrapping (Pending)
The goal is to ensure the repository remains extremely lightweight while still containing the structural boundaries needed to seamlessly rebuild the heavy toolchain binaries on any new system.

### Proposed Steps
1. **Clean up git tracking**: Currently, the `bin/arduino-cli` executable and the compiled `CH341SER` kernel driver objects are tracked. We will `git rm --cached` these heavy compiled artifacts.
2. **Add structural `.gitkeep`s**: Create `.gitkeep` files in `bin/` and `arduino_data/` to track the directories without their contents. Update `.gitignore` to ignore the actual contents (`bin/*`, `arduino_data/*`) to prevent blobs in our history.
3. **Enhance `setup_env.sh`**: Adjust the environment setup script to automatically execute the `curl` installer if `bin/arduino-cli` does not exist, and subsequently issue `arduino-cli core install` and `arduino-cli lib install` commands if the directories in `arduino_data/` are missing.

### Verification Plan
- `git status` should not track any compiled `.o`, `.ko`, or executable blob files.
- Purging `bin/` and running `./setup_env.sh` successfully re-installs everything.

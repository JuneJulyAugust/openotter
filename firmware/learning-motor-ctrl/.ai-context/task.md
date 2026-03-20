# Arduino Mega 2560 Project

## Phase 1: Connect Arduino Mega 2560 to Jetson (Completed)
- [x] Capture initial disconnected state (lsusb, devices)
- [x] Connect Arduino Mega 2560 to Jetson
  - [x] Prompt user to connect the board
  - [x] Capture connected state and find differences
  - [x] Get device information (e.g., /dev/ttyACM* or /dev/ttyUSB*)
- [x] Load required kernel models/modules
  - [x] Identify necessary kernel modules (e.g., cdc_acm, ch341) - Module missing
  - [x] Download CH341 driver source code
  - [x] Compile driver using make
  - [x] Install driver and load module
- [x] Verify connection and serial communication
- [x] Organize `.ai_context` and commit to git

## Phase 2: Servo Motor Demo (Completed)
- [x] Document the servo hardware connection
- [x] Install and configure `arduino-cli` environment
- [x] Write the servo sweep demo sketch (`servo_demo/servo_demo.ino`)
- [x] Compile the sketch for `arduino:avr:mega`
- [x] Upload the sketch to `/dev/ttyUSB0`
- [x] Verify the servo sweeps back and forth

## Phase 3: Control Scripts and Documentation (Completed)
- [x] Write a `servo_stop` Arduino sketch to center and shut down the servo PWM.
- [x] Write a `run_servo.sh` bash script to easily compile and flash the `servo_demo` sketch.
- [x] Write a `stop_servo.sh` bash script to easily compile and flash the `servo_stop` sketch.
- [x] Write `setup_env.sh` to configure the environment variables for `arduino-cli`.
- [x] Create a comprehensive `README.md` explaining setup, dependencies (like where libraries live), and how to run the scripts.

## Phase 4: Localize Arduino Environment (Completed)
- [x] Initialize local `arduino-cli.yaml` configuration.
- [x] Configure toolchain and libraries directory point to `arduino_data`.
- [x] Migrate `~/.arduino15` contents to `./arduino_data`.
- [x] Update `setup_env.sh` and wrapper scripts to use local `arduino-cli.yaml`.
- [x] Update `README.md` to reflect local library structure and ignore `arduino_data/` in Git.
- [x] Delete `~/.arduino15` to confirm separation.

## Phase 5: Project Organization and Bootstrapping (Completed)
- [x] Add `.gitkeep` to `bin/` and `arduino_data/` to track directory structures.
- [x] Update `.gitignore` to specifically ignore all contents in `bin/` and `arduino_data/` except `.gitkeep`.
- [x] Remove currently tracked binaries like `bin/arduino-cli` and compiled driver files from git using `git rm --cached`.
- [x] Refactor `setup_env.sh` to automatically download and install `arduino-cli`, the AVR core, and the Servo library if they are missing.

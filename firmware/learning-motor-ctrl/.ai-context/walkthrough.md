# Arduino Mega 2560 Development Log

This document tracks our step-by-step development process, goals, executed commands, and results for the Arduino Mega 2560 project.

## Step 1: Capture Initial Disconnected State
**Goal**: Record the system's USB and serial devices *before* the Arduino is connected, so we can easily identify the changes once it is plugged in.

**Actions**:
Ran the following commands to list current USB devices and serial ports:
```bash
lsusb > /tmp/lsusb_before.txt
ls -l /dev/ttyACM* /dev/ttyUSB* > /tmp/tty_before.txt 2>/dev/null || true
```

**Results**:
- `lsusb` showed standard devices (Apple Keyboard, Mouse, Bluetooth, Hubs).
- No `/dev/ttyACM*` or `/dev/ttyUSB*` serial devices were present on the system.

## Step 2: Connect Arduino and Identify Device
**Goal**: Connect the Arduino Mega 2560 to the Jetson, identify its USB Vendor/Product ID, and find the assigned serial port.

**Actions**:
Prompted the user to physically connect the Arduino to the Jetson via USB. After connection, ran commands to find the new device:
```bash
lsusb > /tmp/lsusb_after.txt
diff /tmp/lsusb_before.txt /tmp/lsusb_after.txt
ls -l /dev/ttyACM* /dev/ttyUSB*
```

**Results**:
- `lsusb` showed a new device: `Bus 001 Device 009: ID 1a86:7523 QinHeng Electronics CH340 serial converter`. This confirms the Arduino uses a CH340 USB-to-serial chip.
- However, listing serial ports `/dev/ttyACM*` and `/dev/ttyUSB*` returned no results. The system recognized the USB device, but did not create a serial port interface for it.

## Step 3: Investigate and Load Kernel Modules
**Goal**: Figure out why the CH340 device didn't get assigned a `ttyUSB` port. Usually, this means the `ch341` kernel module is missing or not loaded.

**Actions**:
Checked loaded kernel modules and system logs, then searched the system's kernel module directory:
```bash
lsmod | grep ch34
sudo dmesg | grep -i usb | tail -n 20
find /lib/modules -name "*ch34*.ko*"
grep -i ch34 /lib/modules/$(uname -r)/modules.builtin
```

**Results**:
- No `ch341` module is currently loaded.
- The `dmesg` logs showed no attempt by any driver to claim the USB device.
- A search for the `ch341.ko` module file in `/lib/modules/` returned no results.
- The module is not built-in to the Jetson's current kernel.
- **Conclusion**: The default Jetson Linux kernel on this device does not include the CH341 serial driver. We will need to compile and install it from source.

## Step 4: Compile and Install CH341 Driver
**Goal**: Download the CH341 driver source code, compile it for the Jetson kernel, and install it.

**Actions**:
Cloned the known Linux driver repository (`juliagoda/CH341SER`), compiled it using `make`, and installed it to the kernel module directory.
```bash
git clone https://github.com/juliagoda/CH341SER.git
cd CH341SER
make
sudo make install
sudo modprobe ch34x
```

**Results**:
- The driver compiled successfully (`ch34x.ko` was created).
- `sudo make install` copied the module to `/lib/modules/5.15.185-tegra/kernel/drivers/usb/serial` and ran `depmod`.
- The `ch34x` module was successfully loaded into the kernel using `modprobe`.

## Step 5: Verify Connection
**Goal**: Check if the newly loaded driver correctly claims the Arduino and creates the `ttyUSB` port.

**Actions**:
Verified the module was loaded and listed the available serial ports:
```bash
lsmod | grep ch34x
ls -l /dev/ttyACM* /dev/ttyUSB*
```

**Results**:
## Step 6: Troubleshoot Serial Port Disconnection
**Goal**: Investigate why `/dev/ttyUSB0` disappeared immediately after being assigned during the first connection check.

**Actions**:
Checked the user's terminal and syslogs (`journalctl -k`).
Discovered that a background service called `brltty` (a Braille display daemon pre-installed on Ubuntu) was claiming the `ch34x` USB interface, preventing it from binding as a serial port.
Ran the following commands to stop and remove `brltty`:
```bash
sudo systemctl stop brltty
sudo apt-get remove -y brltty
sudo rmmod ch34x
sudo modprobe ch34x
```

**Results**:
- The `brltty` package was uninstalled.
- Restarting the `ch34x` driver correctly bound the Arduino Mega 2560 to `/dev/ttyUSB0`.

## Step 7: Project Context and Git Commit
**Goal**: Organize development documents and environment variables, and commit the current stable state to git.

**Actions**:
Created a `.ai_context` directory to house the task list, implementation plan, and walkthrough.
Created an `env.md` file to store the sudo password and other environment context.
Initialized (or used) the local git repository and committed all changes.
```bash
mkdir -p .ai_context
mv task.md walkthrough.md implementation_plan.md .ai_context/
git add .
git commit -m "Initial setup: Add project context and CH341 serial driver source"
```

**Results**:
- Project is now organized and versioned.
- The `CH341SER` source code is preserved in the repository for future reference.
- Next steps are clearly defined in `.ai_context/task.md`.

---

# Phase 2: Servo Control Demo

## Step 1: Document Hardware Connection
**Goal**: Record the physical wiring of the servo motor to the Arduino Main Board and Sensor Shield.

**Actions**:
Based on the reference image `/disk/projects/arduino_demo/images/arduino_mega_2560_servo_connection.jpeg`, the servo is connected to the PWM section of the Sensor Shield.
Specifically, the control wire of the servo is connected to **PWM Pin 9**.

**Results**:
- Hardware configuration is understood and documented. The Arduino sketch will need to define `pin 9` as the control pin for the `Servo` library.

## Step 2: Write and Upload Demo Sketch
**Goal**: Install `arduino-cli`, install necessary libraries and AVR core, write the setup code for the MG995R torque servo, and upload it via `ttyUSB0`.

**Actions**:
Installed `arduino-cli` directly via the standard shell script install method.
Wrote `servo_demo/servo_demo.ino`, configuring the library for a standard 180-degree sweep on Pin 9.
Adjusted permissions for `chmod 666 /dev/ttyUSB0` so that `arduino-cli` could write the binary image to the controller.
```bash
arduino-cli core install arduino:avr
arduino-cli lib install Servo
arduino-cli compile --fqbn arduino:avr:mega servo_demo/
arduino-cli upload -p /dev/ttyUSB0 --fqbn arduino:avr:mega servo_demo/
```

**Results**:
- Binary compiled successfully and flashed over UART without errors. The Arduino immediately began moving the MG995R servo.

## Step 3: Wrapper Scripts and Documentation
**Goal**: Provide an easy way to switch the servo to stop or run using high-level terminal bash scripts.

**Actions**:
Created `servo_stop/servo_stop.ino` to center the servo at exactly 90 degrees and detach the PWM entirely, preventing hardware jitter.
Created executable shell scripts `run_servo.sh`, `stop_servo.sh`, and `setup_env.sh` to abstract away the compiled commands.
Created a `README.md` at the project root covering dependencies like `arduino-cli` and the `Servo` library locations.
```bash
chmod +x *.sh
./stop_servo.sh
```

**Results**:
- The user can start sweeping by typing `./run_servo.sh`.
- The user can stop all movement cleanly by typing `./stop_servo.sh`.
- Complete environment details are comprehensively documented in the `README.md`.

## Step 5: Improve Robustness and Path Resolution
**Goal**: Ensure all scripts work regardless of the current working directory by resolving absolute paths.

**Actions**:
Modified `tools/common.sh` and `tools/setup_env.sh` to export `ARDUINO_DIRECTORIES_DATA`, `ARDUINO_DIRECTORIES_USER`, and `ARDUINO_DIRECTORIES_DOWNLOADS` as absolute paths derived from the script's location.
Modified all high-level scripts in `scripts/` to use an absolute `$SKETCHES_DIR` variable when calling `compile_and_upload`.
Removed relative directory paths from `arduino-cli.yaml` to avoid conflicts with environment variables.

**Results**:
- Scripts can now be executed from the project root (e.g., `bash scripts/run_servo.sh`) or from within the `scripts/` directory without path errors.
- `arduino-cli` consistently uses the local `tools/arduino_data` directory regardless of the execution context.


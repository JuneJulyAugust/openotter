# Host unit tests for HAL-free firmware modules.
# Run:  make test

CC      ?= cc
CFLAGS  ?= -std=c11 -Wall -Wextra -Werror -O0 -g
INCDIR   = -I ../../Core/Inc
BUILD_DIR = build

TESTS = test_tof_l1_roi test_rev_safety test_rev_safety_tof test_rev_safety_l5 test_tof_frame_codec test_tof_l5_config test_ble_tof_policy test_pwm_control test_ble_command test_ble_gatt_layout test_tof_l5_debounce test_firmware_panic test_firmware_watchdog test_ble_attr_dispatch test_firmware_stack_guard
TARGETS = $(addprefix $(BUILD_DIR)/,$(TESTS))

.PHONY: all test clean dirs

all: dirs $(TARGETS)

dirs:
	@mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/test_tof_l1_roi: test_tof_l1_roi.c ../../Core/Src/tof_l1_roi.c ../../Core/Inc/tof_l1.h | dirs
	$(CC) $(CFLAGS) $(INCDIR) test_tof_l1_roi.c ../../Core/Src/tof_l1_roi.c -o $@

$(BUILD_DIR)/test_rev_safety: test_rev_safety.c ../../Core/Src/rev_safety.c ../../Core/Inc/rev_safety.h | dirs
	$(CC) $(CFLAGS) $(INCDIR) test_rev_safety.c ../../Core/Src/rev_safety.c -o $@ -lm

$(BUILD_DIR)/test_rev_safety_tof: test_rev_safety_tof.c ../../Core/Src/rev_safety_tof.c ../../Core/Inc/rev_safety_tof.h | dirs
	$(CC) $(CFLAGS) $(INCDIR) test_rev_safety_tof.c ../../Core/Src/rev_safety_tof.c -o $@

$(BUILD_DIR)/test_rev_safety_l5: test_rev_safety_l5.c ../../Core/Src/rev_safety_l5.c ../../Core/Src/rev_safety_tof.c ../../Core/Inc/rev_safety_l5.h ../../Core/Inc/rev_safety_tof.h ../../Core/Inc/tof_types.h | dirs
	$(CC) $(CFLAGS) $(INCDIR) test_rev_safety_l5.c ../../Core/Src/rev_safety_l5.c ../../Core/Src/rev_safety_tof.c -o $@

$(BUILD_DIR)/test_tof_frame_codec: test_tof_frame_codec.c ../../Core/Src/tof_frame_codec.c ../../Core/Inc/tof_frame_codec.h ../../Core/Inc/tof_types.h | dirs
	$(CC) $(CFLAGS) $(INCDIR) test_tof_frame_codec.c ../../Core/Src/tof_frame_codec.c -o $@

$(BUILD_DIR)/test_tof_l5_config: test_tof_l5_config.c ../../Core/Src/tof_l5_config.c ../../Core/Inc/tof_l5.h ../../Core/Inc/tof_types.h | dirs
	$(CC) $(CFLAGS) $(INCDIR) test_tof_l5_config.c ../../Core/Src/tof_l5_config.c -o $@

$(BUILD_DIR)/test_ble_tof_policy: test_ble_tof_policy.c ../../Core/Src/ble_tof_policy.c ../../Core/Inc/ble_tof_policy.h ../../Core/Inc/tof_types.h | dirs
	$(CC) $(CFLAGS) $(INCDIR) test_ble_tof_policy.c ../../Core/Src/ble_tof_policy.c -o $@

$(BUILD_DIR)/test_pwm_control: test_pwm_control.c ../../Core/Src/pwm_control.c ../../Core/Inc/pwm_control.h | dirs
	$(CC) $(CFLAGS) $(INCDIR) test_pwm_control.c ../../Core/Src/pwm_control.c -o $@

$(BUILD_DIR)/test_ble_command: test_ble_command.c ../../Core/Src/ble_command.c ../../Core/Inc/ble_command.h | dirs
	$(CC) $(CFLAGS) $(INCDIR) test_ble_command.c ../../Core/Src/ble_command.c -o $@

$(BUILD_DIR)/test_ble_gatt_layout: test_ble_gatt_layout.c ../../Core/Src/ble_gatt_layout.c ../../Core/Inc/ble_gatt_layout.h | dirs
	$(CC) $(CFLAGS) $(INCDIR) test_ble_gatt_layout.c ../../Core/Src/ble_gatt_layout.c -o $@

$(BUILD_DIR)/test_tof_l5_debounce: test_tof_l5_debounce.c ../../Core/Src/tof_l5_debounce.c ../../Core/Inc/tof_l5_debounce.h | dirs
	$(CC) $(CFLAGS) $(INCDIR) test_tof_l5_debounce.c ../../Core/Src/tof_l5_debounce.c -o $@

# firmware_panic.c references TIM3/USART1 register names from stm32l4xx.h on
# target builds; HOST_TEST disables those references for the host harness.
$(BUILD_DIR)/test_firmware_panic: test_firmware_panic.c ../../Core/Src/firmware_panic.c ../../Core/Inc/firmware_panic.h ../../Core/Inc/pwm_control.h | dirs
	$(CC) $(CFLAGS) $(INCDIR) -DHOST_TEST test_firmware_panic.c ../../Core/Src/firmware_panic.c -o $@

# firmware_watchdog.c uses HAL IWDG types under target build. HOST_TEST
# isolates the pure prescaler/reload math for host-side coverage.
$(BUILD_DIR)/test_firmware_watchdog: test_firmware_watchdog.c ../../Core/Src/firmware_watchdog.c ../../Core/Inc/firmware_watchdog.h | dirs
	$(CC) $(CFLAGS) $(INCDIR) -DHOST_TEST test_firmware_watchdog.c ../../Core/Src/firmware_watchdog.c -o $@

$(BUILD_DIR)/test_ble_attr_dispatch: test_ble_attr_dispatch.c ../../Core/Src/ble_attr_dispatch.c ../../Core/Inc/ble_attr_dispatch.h | dirs
	$(CC) $(CFLAGS) $(INCDIR) test_ble_attr_dispatch.c ../../Core/Src/ble_attr_dispatch.c -o $@

# firmware_stack_guard.c references linker-provided symbols on the target;
# HOST_TEST exposes only the pure address-math helper for host coverage.
$(BUILD_DIR)/test_firmware_stack_guard: test_firmware_stack_guard.c ../../Core/Src/firmware_stack_guard.c ../../Core/Inc/firmware_stack_guard.h | dirs
	$(CC) $(CFLAGS) $(INCDIR) -DHOST_TEST test_firmware_stack_guard.c ../../Core/Src/firmware_stack_guard.c -o $@

test: all
	@set -e; for t in $(TESTS); do echo "=== $$t ==="; $(BUILD_DIR)/$$t; done

clean:
	rm -rf $(BUILD_DIR)

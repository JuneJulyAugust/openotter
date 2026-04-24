# Host unit tests for HAL-free firmware modules.
# Run:  make test

CC      ?= cc
CFLAGS  ?= -std=c11 -Wall -Wextra -Werror -O0 -g
INCDIR   = -I ../../Core/Inc
BUILD_DIR = build

TESTS = test_tof_l1_roi test_rev_safety test_rev_safety_tof test_tof_frame_codec test_tof_l5_config test_ble_tof_policy
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

$(BUILD_DIR)/test_tof_frame_codec: test_tof_frame_codec.c ../../Core/Src/tof_frame_codec.c ../../Core/Inc/tof_frame_codec.h ../../Core/Inc/tof_types.h | dirs
	$(CC) $(CFLAGS) $(INCDIR) test_tof_frame_codec.c ../../Core/Src/tof_frame_codec.c -o $@

$(BUILD_DIR)/test_tof_l5_config: test_tof_l5_config.c ../../Core/Src/tof_l5_config.c ../../Core/Inc/tof_l5.h ../../Core/Inc/tof_types.h | dirs
	$(CC) $(CFLAGS) $(INCDIR) test_tof_l5_config.c ../../Core/Src/tof_l5_config.c -o $@

$(BUILD_DIR)/test_ble_tof_policy: test_ble_tof_policy.c ../../Core/Src/ble_tof_policy.c ../../Core/Inc/ble_tof_policy.h ../../Core/Inc/tof_types.h | dirs
	$(CC) $(CFLAGS) $(INCDIR) test_ble_tof_policy.c ../../Core/Src/ble_tof_policy.c -o $@

test: all
	@set -e; for t in $(TESTS); do echo "=== $$t ==="; $(BUILD_DIR)/$$t; done

clean:
	rm -rf $(BUILD_DIR)

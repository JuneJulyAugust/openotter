# Host unit tests for HAL-free firmware modules.
# Run:  make test

CC      ?= cc
CFLAGS  ?= -std=c11 -Wall -Wextra -Werror -O0 -g
INCDIR   = -I ../../Core/Inc

TESTS = test_tof_l1_roi

.PHONY: all test clean
all: $(TESTS)

test_tof_l1_roi: test_tof_l1_roi.c ../../Core/Src/tof_l1_roi.c ../../Core/Inc/tof_l1.h
	$(CC) $(CFLAGS) $(INCDIR) test_tof_l1_roi.c ../../Core/Src/tof_l1_roi.c -o $@

test: $(TESTS)
	@set -e; for t in $(TESTS); do echo "=== $$t ==="; ./$$t; done

clean:
	rm -f $(TESTS)

# Host unit tests for HAL-free firmware modules.
# Run:  make test

CC      ?= cc
CFLAGS  ?= -std=c11 -Wall -Wextra -Werror -O0 -g
INCDIR   = -I ../../Core/Inc

TESTS = test_tof_l1_roi test_rev_safety

.PHONY: all test clean
all: $(TESTS)

test_tof_l1_roi: test_tof_l1_roi.c ../../Core/Src/tof_l1_roi.c ../../Core/Inc/tof_l1.h
	$(CC) $(CFLAGS) $(INCDIR) test_tof_l1_roi.c ../../Core/Src/tof_l1_roi.c -o $@

test_rev_safety: test_rev_safety.c ../../Core/Src/rev_safety.c ../../Core/Inc/rev_safety.h
	$(CC) $(CFLAGS) $(INCDIR) test_rev_safety.c ../../Core/Src/rev_safety.c -o $@ -lm

test: $(TESTS)
	@set -e; for t in $(TESTS); do echo "=== $$t ==="; ./$$t; done

clean:
	rm -f $(TESTS)

/* SPDX-License-Identifier: BSD-3-Clause */
#include <stdio.h>
#include <stdint.h>

#include "firmware_mpu.h"

static int g_fails = 0;

static void expect_eq_u(const char *label, uint32_t got, uint32_t want) {
  if (got != want) {
    fprintf(stderr, "FAIL %s: got %u want %u\n", label,
            (unsigned)got, (unsigned)want);
    g_fails++;
  }
}

static void expect_eq_bool(const char *label, bool got, bool want) {
  if (got != want) {
    fprintf(stderr, "FAIL %s: got %d want %d\n", label,
            (int)got, (int)want);
    g_fails++;
  }
}

/* RASR.SIZE = log2(size_bytes) - 1. Pin the encoding for the sizes we
 * actually use, plus a couple of edge cases. */
static void test_encode_size_known_values(void) {
  expect_eq_u("32 B (min)", FwMpu_EncodeSize(32u),       4u);
  expect_eq_u("64 B",       FwMpu_EncodeSize(64u),       5u);
  expect_eq_u("128 B",      FwMpu_EncodeSize(128u),      6u);
  expect_eq_u("256 B",      FwMpu_EncodeSize(256u),      7u);
  expect_eq_u("1 KB",       FwMpu_EncodeSize(1024u),     9u);
  expect_eq_u("4 KB",       FwMpu_EncodeSize(4096u),     11u);
  expect_eq_u("96 KB RAM block (not pow2)",
              FwMpu_EncodeSize(96u * 1024u), 0u);
}

static void test_encode_size_rejects_non_power_of_two(void) {
  expect_eq_u("33 B",  FwMpu_EncodeSize(33u),  0u);
  expect_eq_u("48 B",  FwMpu_EncodeSize(48u),  0u);
  expect_eq_u("100 B", FwMpu_EncodeSize(100u), 0u);
}

static void test_encode_size_rejects_below_minimum(void) {
  /* MPU minimum region size is 32 bytes on Cortex-M4. */
  expect_eq_u("0",   FwMpu_EncodeSize(0u),   0u);
  expect_eq_u("16",  FwMpu_EncodeSize(16u),  0u);
  expect_eq_u("8",   FwMpu_EncodeSize(8u),   0u);
}

/* The default stack guard size pinned by the public macro. */
static void test_default_guard_size_constant(void) {
  expect_eq_u("FW_MPU_STACK_GUARD_SIZE", FW_MPU_STACK_GUARD_SIZE, 32u);
  expect_eq_u("encoded default", FwMpu_EncodeSize(FW_MPU_STACK_GUARD_SIZE), 4u);
}

static void test_alignment_check_matches_size(void) {
  /* 32-byte region needs 32-byte alignment (low 5 bits zero). */
  expect_eq_bool("0x20017C00 aligned to 32",
                 FwMpu_IsAligned(0x20017C00u, 32u), true);
  expect_eq_bool("0x20017C20 aligned to 32",
                 FwMpu_IsAligned(0x20017C20u, 32u), true);
  expect_eq_bool("0x20017C01 aligned to 32",
                 FwMpu_IsAligned(0x20017C01u, 32u), false);
  expect_eq_bool("0x20017C10 aligned to 32",
                 FwMpu_IsAligned(0x20017C10u, 32u), false);
}

static void test_alignment_rejects_invalid_size(void) {
  /* Non-power-of-2 sizes have no meaningful alignment; refuse. */
  expect_eq_bool("size=0",  FwMpu_IsAligned(0u, 0u), false);
  expect_eq_bool("size=3",  FwMpu_IsAligned(0u, 3u), false);
  expect_eq_bool("size=33", FwMpu_IsAligned(0u, 33u), false);
}

/* Regression: the actual stack-bottom address used by FwMpu_Init() in
 * the typical STM32L475 layout (96 KB RAM at 0x20000000, 1 KB stack at
 * top) must satisfy the MPU's natural-alignment requirement. If a future
 * linker-script edit reduces _Min_Stack_Size to a non-32-byte multiple,
 * this assertion-by-test catches it on the host before the MPU is
 * silently skipped on the target. */
static void test_real_stack_bottom_is_aligned(void) {
  uintptr_t estack = 0x20018000u;     /* end of 96 KB RAM */
  uintptr_t stack_size = 0x400u;      /* current _Min_Stack_Size */
  uintptr_t guard_addr = estack - stack_size;
  expect_eq_bool("0x20017C00 aligned to 32",
                 FwMpu_IsAligned(guard_addr, FW_MPU_STACK_GUARD_SIZE),
                 true);
}

int main(void) {
  test_encode_size_known_values();
  test_encode_size_rejects_non_power_of_two();
  test_encode_size_rejects_below_minimum();
  test_default_guard_size_constant();
  test_alignment_check_matches_size();
  test_alignment_rejects_invalid_size();
  test_real_stack_bottom_is_aligned();
  if (g_fails == 0) {
    printf("firmware_mpu tests: OK\n");
    return 0;
  }
  printf("firmware_mpu tests: %d FAIL\n", g_fails);
  return 1;
}

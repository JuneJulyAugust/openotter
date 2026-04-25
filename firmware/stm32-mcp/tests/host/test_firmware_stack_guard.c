/* SPDX-License-Identifier: BSD-3-Clause */
#include <stdio.h>
#include <stdint.h>

#include "firmware_stack_guard.h"

static int g_fails = 0;

static void expect_eq_ptr(const char *label, uintptr_t got, uintptr_t want) {
  if (got != want) {
    fprintf(stderr, "FAIL %s: got 0x%lx want 0x%lx\n", label,
            (unsigned long)got, (unsigned long)want);
    g_fails++;
  }
}

static void test_normal_address_subtraction(void) {
  /* Typical STM32L4 layout: RAM ends at 0x20018000 (96 KB at 0x20000000).
   * Stack size 1 KB → bottom at 0x20017C00. */
  expect_eq_ptr("96 KB RAM, 1 KB stack",
                FwStackGuard_BottomAddress(0x20018000u, 0x400u),
                0x20017C00u);
}

static void test_zero_estack_returns_zero(void) {
  expect_eq_ptr("estack=0", FwStackGuard_BottomAddress(0u, 0x400u), 0u);
}

static void test_zero_stack_size_returns_zero(void) {
  /* A zero stack size would mean the bottom is at the top — pointless and
   * almost certainly a config bug; safer to refuse to stamp anything. */
  expect_eq_ptr("size=0", FwStackGuard_BottomAddress(0x20018000u, 0u), 0u);
}

static void test_size_larger_than_estack_returns_zero(void) {
  /* Underflow guard: must not return a wrap-around address that would
   * point into peripheral or SCB MMIO space. */
  expect_eq_ptr("size > estack",
                FwStackGuard_BottomAddress(0x100u, 0x400u), 0u);
  expect_eq_ptr("size == estack",
                FwStackGuard_BottomAddress(0x400u, 0x400u), 0u);
}

static void test_magic_constant_is_recognizable(void) {
  /* The magic itself is referenced elsewhere; pinning it here catches
   * an accidental edit that would silently disable the guard. */
  if (FW_STACK_GUARD_MAGIC != 0xDEADBEEFu) {
    fprintf(stderr, "FAIL magic: got 0x%lx want 0xDEADBEEF\n",
            (unsigned long)FW_STACK_GUARD_MAGIC);
    g_fails++;
  }
}

int main(void) {
  test_normal_address_subtraction();
  test_zero_estack_returns_zero();
  test_zero_stack_size_returns_zero();
  test_size_larger_than_estack_returns_zero();
  test_magic_constant_is_recognizable();
  if (g_fails == 0) {
    printf("firmware_stack_guard tests: OK\n");
    return 0;
  }
  printf("firmware_stack_guard tests: %d FAIL\n", g_fails);
  return 1;
}

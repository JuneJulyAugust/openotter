/* SPDX-License-Identifier: BSD-3-Clause */
#include <stdio.h>
#include <stdint.h>

#include "ble_attr_dispatch.h"

static int g_fails = 0;

static void expect_eq_bool(const char *label, bool got, bool want) {
  if (got != want) {
    fprintf(stderr, "FAIL %s: got %d want %d\n", label, (int)got, (int)want);
    g_fails++;
  }
}

static void test_matches_value_handle(void) {
  /* Typical case: characteristic handle is 0x10, value lives at 0x11. */
  expect_eq_bool("char=0x10 value=0x11",
                 BleAttrDispatch_IsValueWrite(0x11u, 0x10u), true);
}

static void test_does_not_match_declaration_handle(void) {
  /* The declaration handle itself (== char_handle) is not the value
   * descriptor. A write to it would be malformed but must not match. */
  expect_eq_bool("char=0x10 attr=0x10 (decl)",
                 BleAttrDispatch_IsValueWrite(0x10u, 0x10u), false);
}

static void test_does_not_match_cccd_or_other_offsets(void) {
  /* CCCD typically lands at value+1; far handles must not match either. */
  expect_eq_bool("char=0x10 attr=0x12",
                 BleAttrDispatch_IsValueWrite(0x12u, 0x10u), false);
  expect_eq_bool("char=0x10 attr=0x00",
                 BleAttrDispatch_IsValueWrite(0x00u, 0x10u), false);
  expect_eq_bool("char=0x10 attr=0xFFFF",
                 BleAttrDispatch_IsValueWrite(0xFFFFu, 0x10u), false);
}

/* This is the regression test for the FE44 misroute class:
 *
 * If aci_gatt_add_char() fails (e.g. Max_Attribute_Records exhausted), the
 * caller's char_handle stays 0. The naïve comparison
 *   attr_handle == (char_handle + 1)
 * then matches attribute handle 1 — which BlueNRG-MS assigns to the
 * GATT service declaration of every service. Any attribute write at
 * all (e.g. a write to a different characteristic on the same connection)
 * would get routed into the command parser. A malicious or buggy
 * client could then drive steering/throttle/mode without ever discovering
 * the real characteristic.
 *
 * BleAttrDispatch_IsValueWrite() must reject this regardless of the
 * received handle. */
static void test_uninitialized_char_handle_never_matches(void) {
  expect_eq_bool("char=0 attr=0 (uninit, write to GATT service decl)",
                 BleAttrDispatch_IsValueWrite(0x0000u, 0x0000u), false);
  expect_eq_bool("char=0 attr=1 (uninit, naive +1 trap)",
                 BleAttrDispatch_IsValueWrite(0x0001u, 0x0000u), false);
  expect_eq_bool("char=0 attr=0x42 (uninit, arbitrary handle)",
                 BleAttrDispatch_IsValueWrite(0x0042u, 0x0000u), false);
}

static void test_handle_overflow_safety(void) {
  /* If a service ever ends up with char_handle == 0xFFFF, the +1 wraps
   * to 0. The current implementation accepts that; the test pins the
   * behavior so a future tightening doesn't accidentally start matching
   * spurious attribute 0 writes. */
  expect_eq_bool("char=0xFFFF attr=0 (wrap)",
                 BleAttrDispatch_IsValueWrite(0x0000u, 0xFFFFu), true);
  expect_eq_bool("char=0xFFFF attr=0xFFFF",
                 BleAttrDispatch_IsValueWrite(0xFFFFu, 0xFFFFu), false);
}

int main(void) {
  test_matches_value_handle();
  test_does_not_match_declaration_handle();
  test_does_not_match_cccd_or_other_offsets();
  test_uninitialized_char_handle_never_matches();
  test_handle_overflow_safety();
  if (g_fails == 0) {
    printf("ble_attr_dispatch tests: OK\n");
    return 0;
  }
  printf("ble_attr_dispatch tests: %d FAIL\n", g_fails);
  return 1;
}

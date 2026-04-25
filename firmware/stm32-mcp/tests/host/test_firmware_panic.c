/* SPDX-License-Identifier: BSD-3-Clause */
#include <stdio.h>

#include "firmware_panic.h"

static int g_fails = 0;

static void expect_eq_char(const char *label, char got, char want) {
  if (got != want) {
    fprintf(stderr, "FAIL %s: got '%c' want '%c'\n", label, got, want);
    g_fails++;
  }
}

static void test_known_reasons_map_to_distinct_tags(void) {
  expect_eq_char("hard fault",  Firmware_PanicTag(FW_PANIC_HARD_FAULT),  'H');
  expect_eq_char("mem manage",  Firmware_PanicTag(FW_PANIC_MEM_MANAGE),  'M');
  expect_eq_char("bus fault",   Firmware_PanicTag(FW_PANIC_BUS_FAULT),   'B');
  expect_eq_char("usage fault", Firmware_PanicTag(FW_PANIC_USAGE_FAULT), 'U');
  expect_eq_char("nmi",         Firmware_PanicTag(FW_PANIC_NMI),         'N');
  expect_eq_char("assert",      Firmware_PanicTag(FW_PANIC_ASSERT),      'A');
  expect_eq_char("stack",       Firmware_PanicTag(FW_PANIC_STACK),       'S');
}

static void test_none_and_unknown_map_to_sentinel(void) {
  expect_eq_char("none",     Firmware_PanicTag(FW_PANIC_NONE), '?');
  /* Out-of-band value should not crash the mapping. */
  expect_eq_char("garbage",  Firmware_PanicTag((Firmware_PanicReason_t)42), '?');
}

static void test_tags_are_unique(void) {
  /* The serial-log parser looks for one byte after "PANIC:". Two reasons
   * mapping to the same tag would silently confuse triage. */
  Firmware_PanicReason_t reasons[] = {
    FW_PANIC_HARD_FAULT, FW_PANIC_MEM_MANAGE, FW_PANIC_BUS_FAULT,
    FW_PANIC_USAGE_FAULT, FW_PANIC_NMI, FW_PANIC_ASSERT,
    FW_PANIC_STACK,
  };
  size_t n = sizeof(reasons) / sizeof(reasons[0]);
  for (size_t i = 0; i < n; ++i) {
    for (size_t j = i + 1; j < n; ++j) {
      if (Firmware_PanicTag(reasons[i]) == Firmware_PanicTag(reasons[j])) {
        fprintf(stderr, "FAIL tag collision: reasons %d and %d both map to '%c'\n",
                (int)reasons[i], (int)reasons[j],
                Firmware_PanicTag(reasons[i]));
        g_fails++;
      }
    }
  }
}

int main(void) {
  test_known_reasons_map_to_distinct_tags();
  test_none_and_unknown_map_to_sentinel();
  test_tags_are_unique();
  if (g_fails == 0) {
    printf("firmware_panic tests: OK\n");
    return 0;
  }
  printf("firmware_panic tests: %d FAIL\n", g_fails);
  return 1;
}

/* SPDX-License-Identifier: BSD-3-Clause */
#include <stdio.h>

#include "ble_gatt_layout.h"

static int g_fails = 0;

static void expect_eq(const char *label, unsigned got, unsigned want) {
  if (got != want) {
    fprintf(stderr, "FAIL %s: got %u want %u\n", label, got, want);
    g_fails++;
  }
}

static void test_empty_service(void) {
  expect_eq("service-only, NULL chars", BleGattLayout_RequiredSlots(NULL, 0), 1u);
  expect_eq("service-only, 0 chars",
            BleGattLayout_RequiredSlots((const BleGattCharSpec_t *)1, 0), 1u);
}

static void test_single_write_only_char(void) {
  /* Write or write-without-response: decl + value = 2; total with service = 3. */
  BleGattCharSpec_t chars[] = {
    { .notify = false, .indicate = false },
  };
  expect_eq("1 write-only char", BleGattLayout_RequiredSlots(chars, 1), 3u);
}

static void test_single_notify_char(void) {
  /* Notify: decl + value + CCCD = 3; total with service = 4. */
  BleGattCharSpec_t chars[] = {
    { .notify = true, .indicate = false },
  };
  expect_eq("1 notify char", BleGattLayout_RequiredSlots(chars, 1), 4u);
}

static void test_single_indicate_char(void) {
  /* Indicate also consumes a CCCD slot. */
  BleGattCharSpec_t chars[] = {
    { .notify = false, .indicate = true },
  };
  expect_eq("1 indicate char", BleGattLayout_RequiredSlots(chars, 1), 4u);
}

/* This is the regression test for the FE44 GATT slot bug.
 *
 * The FE40 control service has four characteristics with these property mixes:
 *   FE41 cmd     write/wwr           — no CCCD → 2 slots
 *   FE42 status  notify+read         — CCCD    → 3 slots
 *   FE43 safety  notify+read         — CCCD    → 3 slots
 *   FE44 mode    write/wwr/read      — no CCCD → 2 slots
 * Total: 1 (service decl) + 2 + 3 + 3 + 2 = 11
 *
 * Earlier code used 10, which made FE44's add_char silently fail.
 */
static void test_fe40_control_service_layout_is_11(void) {
  BleGattCharSpec_t fe40_chars[] = {
    { .notify = false, .indicate = false }, /* FE41 cmd */
    { .notify = true,  .indicate = false }, /* FE42 status */
    { .notify = true,  .indicate = false }, /* FE43 safety */
    { .notify = false, .indicate = false }, /* FE44 mode */
  };
  expect_eq("FE40 service requires 11 slots",
            BleGattLayout_RequiredSlots(fe40_chars, 4), 11u);
}

/*
 * Reference layout for the FE60 ToF service (cmd + frame + status):
 *   FE61 config  write+read   — no CCCD → 2 slots
 *   FE62 frame   notify       — CCCD    → 3 slots
 *   FE63 status  notify+read  — CCCD    → 3 slots
 * Total: 1 + 2 + 3 + 3 = 9
 */
static void test_fe60_tof_service_layout_is_9(void) {
  BleGattCharSpec_t fe60_chars[] = {
    { .notify = false, .indicate = false }, /* FE61 config */
    { .notify = true,  .indicate = false }, /* FE62 frame */
    { .notify = true,  .indicate = false }, /* FE63 status */
  };
  expect_eq("FE60 service requires 9 slots",
            BleGattLayout_RequiredSlots(fe60_chars, 3), 9u);
}

static void test_notify_and_indicate_combined_only_one_cccd(void) {
  /* GATT only allocates one CCCD per characteristic regardless of whether it
   * supports notify, indicate, or both. */
  BleGattCharSpec_t chars[] = {
    { .notify = true, .indicate = true },
  };
  expect_eq("notify+indicate = 1 CCCD",
            BleGattLayout_RequiredSlots(chars, 1), 4u);
}

int main(void) {
  test_empty_service();
  test_single_write_only_char();
  test_single_notify_char();
  test_single_indicate_char();
  test_fe40_control_service_layout_is_11();
  test_fe60_tof_service_layout_is_9();
  test_notify_and_indicate_combined_only_one_cccd();
  if (g_fails == 0) {
    printf("ble_gatt_layout tests: OK\n");
    return 0;
  }
  printf("ble_gatt_layout tests: %d FAIL\n", g_fails);
  return 1;
}

/* SPDX-License-Identifier: BSD-3-Clause */
#include <stdio.h>
#include <string.h>

#include "ble_command.h"

static int g_fails = 0;

static void expect_eq_int(const char *label, int got, int want) {
  if (got != want) {
    fprintf(stderr, "FAIL %s: got %d want %d\n", label, got, want);
    g_fails++;
  }
}

static void test_parses_valid_6_byte_payload(void) {
  /* steering=1480, throttle=1620, velocity=-150 mm/s
   *   1480 = 0x05C8 → 0xC8 0x05
   *   1620 = 0x0654 → 0x54 0x06
   *   -150 = 0xFF6A → 0x6A 0xFF (two's complement)
   */
  uint8_t bytes[6] = {0xC8, 0x05, 0x54, 0x06, 0x6A, 0xFF};
  BleCommand_t cmd;

  BleCommandStatus_t st = BleCommand_Parse(bytes, sizeof(bytes), &cmd);

  expect_eq_int("status",   st, BLE_CMD_OK);
  expect_eq_int("steering", cmd.steering_us, 1480);
  expect_eq_int("throttle", cmd.throttle_us, 1620);
  expect_eq_int("velocity", cmd.velocity_mm_per_s, -150);
}

static void test_rejects_short_legacy_4_byte_payload(void) {
  /* The pre-v0.4.0 4-byte payload (steering+throttle, no velocity) must be
   * rejected. Reverse safety needs the velocity field to compute the
   * critical distance. */
  uint8_t bytes[4] = {0xC8, 0x05, 0x54, 0x06};
  BleCommand_t cmd;

  BleCommandStatus_t st = BleCommand_Parse(bytes, sizeof(bytes), &cmd);

  expect_eq_int("legacy 4-byte rejected", st, BLE_CMD_TOO_SHORT);
}

static void test_rejects_zero_length(void) {
  BleCommand_t cmd;
  BleCommandStatus_t st = BleCommand_Parse((const uint8_t *)"", 0, &cmd);
  expect_eq_int("len=0 rejected", st, BLE_CMD_TOO_SHORT);
}

static void test_rejects_null(void) {
  BleCommand_t cmd;
  BleCommandStatus_t st1 = BleCommand_Parse(NULL, 6, &cmd);
  uint8_t bytes[6] = {0};
  BleCommandStatus_t st2 = BleCommand_Parse(bytes, 6, NULL);
  expect_eq_int("null data", st1, BLE_CMD_NULL_INPUT);
  expect_eq_int("null out",  st2, BLE_CMD_NULL_INPUT);
}

static void test_ignores_padding_bytes_after_byte_5(void) {
  /* Some BLE writes may pad up to ATT_MTU. Trailing bytes must not affect
   * the parsed payload. */
  uint8_t bytes[20] = {
    0xDC, 0x05,             /* steering = 1500 */
    0xDC, 0x05,             /* throttle = 1500 */
    0x00, 0x00,             /* velocity = 0 */
    /* padding follows */
    0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x12, 0x34,
    0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0,
  };
  BleCommand_t cmd;

  BleCommandStatus_t st = BleCommand_Parse(bytes, sizeof(bytes), &cmd);

  expect_eq_int("status",   st, BLE_CMD_OK);
  expect_eq_int("steering", cmd.steering_us, 1500);
  expect_eq_int("throttle", cmd.throttle_us, 1500);
  expect_eq_int("velocity", cmd.velocity_mm_per_s, 0);
}

static void test_signed_velocity_extremes(void) {
  /* Velocity is signed: full reverse and full forward speeds must round-trip. */
  uint8_t bytes[6] = {
    0xDC, 0x05,             /* steering = 1500 */
    0xDC, 0x05,             /* throttle = 1500 */
    0x00, 0x80,             /* velocity = INT16_MIN = -32768 */
  };
  BleCommand_t cmd;

  BleCommandStatus_t st = BleCommand_Parse(bytes, sizeof(bytes), &cmd);

  expect_eq_int("status",   st, BLE_CMD_OK);
  expect_eq_int("velocity", cmd.velocity_mm_per_s, -32768);

  bytes[4] = 0xFF;
  bytes[5] = 0x7F;          /* velocity = INT16_MAX = +32767 */
  st = BleCommand_Parse(bytes, sizeof(bytes), &cmd);
  expect_eq_int("velocity max", cmd.velocity_mm_per_s, 32767);
}

int main(void) {
  test_parses_valid_6_byte_payload();
  test_rejects_short_legacy_4_byte_payload();
  test_rejects_zero_length();
  test_rejects_null();
  test_ignores_padding_bytes_after_byte_5();
  test_signed_velocity_extremes();
  if (g_fails == 0) {
    printf("ble_command tests: OK\n");
    return 0;
  }
  printf("ble_command tests: %d FAIL\n", g_fails);
  return 1;
}

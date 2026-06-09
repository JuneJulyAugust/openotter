/* SPDX-License-Identifier: BSD-3-Clause */
#include <stdio.h>

#include "ble_adv_policy.h"

static int g_fails = 0;

static void expect_true(const char *label, int got) {
  if (!got) {
    fprintf(stderr, "FAIL %s: expected true\n", label);
    g_fails++;
  }
}

static void expect_false(const char *label, int got) {
  if (got) {
    fprintf(stderr, "FAIL %s: expected false\n", label);
    g_fails++;
  }
}

static void expect_eq_u(const char *label, unsigned got, unsigned want) {
  if (got != want) {
    fprintf(stderr, "FAIL %s: got %u want %u\n", label, got, want);
    g_fails++;
  }
}

static void test_boot_attempt_is_delayed_briefly(void) {
  BleAdvPolicy_t p;
  BleAdvPolicy_Init(&p, 1000u);

  expect_true("boot pending", p.pending != 0u);
  expect_false("not due immediately", BleAdvPolicy_Due(&p, 1000u, false));
  expect_true("due after initial delay",
              BleAdvPolicy_Due(&p, 1100u, false));
  expect_false("connected suppresses due", BleAdvPolicy_Due(&p, 1100u, true));
}

static void test_success_marks_advertising_active(void) {
  BleAdvPolicy_t p;
  BleAdvPolicy_Init(&p, 0u);
  BleAdvPolicy_OnSuccess(&p);

  expect_false("success clears pending", p.pending != 0u);
  expect_true("success active", p.active != 0u);
  expect_eq_u("success fail count", p.fail_count, 0u);
  expect_false("success not due", BleAdvPolicy_Due(&p, 10000u, false));
}

static void test_failure_backs_off_and_caps(void) {
  BleAdvPolicy_t p;
  BleAdvPolicy_Init(&p, 0u);

  BleAdvPolicy_OnFailure(&p, 1000u);
  expect_true("failure pending", p.pending != 0u);
  expect_false("first retry not immediate", BleAdvPolicy_Due(&p, 1999u, false));
  expect_true("first retry due", BleAdvPolicy_Due(&p, 2000u, false));
  expect_eq_u("first fail count", p.fail_count, 1u);

  BleAdvPolicy_OnFailure(&p, 2000u);
  expect_false("second retry not immediate", BleAdvPolicy_Due(&p, 3999u, false));
  expect_true("second retry due", BleAdvPolicy_Due(&p, 4000u, false));

  BleAdvPolicy_OnFailure(&p, 4000u);
  BleAdvPolicy_OnFailure(&p, 8000u);
  expect_eq_u("delay capped", p.retry_delay_ms, BLE_ADV_RETRY_MAX_MS);
}

static void test_connection_edges_reset_policy(void) {
  BleAdvPolicy_t p;
  BleAdvPolicy_Init(&p, 0u);
  BleAdvPolicy_OnFailure(&p, 1000u);

  BleAdvPolicy_OnConnected(&p);
  expect_false("connected clears pending", p.pending != 0u);
  expect_false("connected clears active adv", p.active != 0u);
  expect_eq_u("connected fail count", p.fail_count, 0u);

  BleAdvPolicy_OnDisconnected(&p, 9000u);
  expect_true("disconnect schedules adv", p.pending != 0u);
  expect_false("disconnect not immediate", BleAdvPolicy_Due(&p, 9099u, false));
  expect_true("disconnect due", BleAdvPolicy_Due(&p, 9100u, false));
}

int main(void) {
  test_boot_attempt_is_delayed_briefly();
  test_success_marks_advertising_active();
  test_failure_backs_off_and_caps();
  test_connection_edges_reset_policy();
  if (g_fails == 0) {
    printf("ble_adv_policy tests: OK\n");
    return 0;
  }
  printf("ble_adv_policy tests: %d FAIL\n", g_fails);
  return 1;
}

#include "ble_connection_policy.h"

#include <stdio.h>

static int g_fails = 0;

static void expect_true(const char *name, int value)
{
  if (!value) {
    printf("FAIL %s\n", name);
    g_fails++;
  }
}

static void expect_false(const char *name, int value)
{
  if (value) {
    printf("FAIL %s\n", name);
    g_fails++;
  }
}

static void test_idle_connection_times_out(void)
{
  BleConnectionPolicy_t policy;
  BleConnectionPolicy_Init(&policy);
  BleConnectionPolicy_OnConnected(&policy, 1000u);

  expect_false("not due before timeout",
               BleConnectionPolicy_ShouldTerminate(
                   &policy, 1000u + BLE_APP_HANDSHAKE_TIMEOUT_MS - 1u));
  expect_true("due at timeout",
              BleConnectionPolicy_ShouldTerminate(
                  &policy, 1000u + BLE_APP_HANDSHAKE_TIMEOUT_MS));
}

static void test_app_activity_satisfies_handshake(void)
{
  BleConnectionPolicy_t policy;
  BleConnectionPolicy_Init(&policy);
  BleConnectionPolicy_OnConnected(&policy, 2000u);
  BleConnectionPolicy_OnAppActivity(&policy);

  expect_false("activity prevents termination",
               BleConnectionPolicy_ShouldTerminate(
                   &policy, 2000u + BLE_APP_HANDSHAKE_TIMEOUT_MS + 5000u));
}

static void test_handshake_pending_only_until_app_activity(void)
{
  BleConnectionPolicy_t policy;
  BleConnectionPolicy_Init(&policy);

  expect_false("idle has no pending handshake",
               BleConnectionPolicy_HandshakePending(&policy));

  BleConnectionPolicy_OnConnected(&policy, 2500u);
  expect_true("fresh connection awaits app handshake",
              BleConnectionPolicy_HandshakePending(&policy));

  BleConnectionPolicy_OnAppActivity(&policy);
  expect_false("app activity completes handshake",
               BleConnectionPolicy_HandshakePending(&policy));

  BleConnectionPolicy_OnDisconnected(&policy);
  expect_false("disconnect clears pending handshake",
               BleConnectionPolicy_HandshakePending(&policy));
}

static void test_terminate_request_is_one_shot(void)
{
  BleConnectionPolicy_t policy;
  BleConnectionPolicy_Init(&policy);
  BleConnectionPolicy_OnConnected(&policy, 3000u);

  expect_true("due before request",
              BleConnectionPolicy_ShouldTerminate(
                  &policy, 3000u + BLE_APP_HANDSHAKE_TIMEOUT_MS));
  BleConnectionPolicy_OnTerminateRequested(&policy);
  expect_false("not due after request",
               BleConnectionPolicy_ShouldTerminate(
                   &policy, 3000u + BLE_APP_HANDSHAKE_TIMEOUT_MS + 1u));
}

static void test_disconnect_resets_policy(void)
{
  BleConnectionPolicy_t policy;
  BleConnectionPolicy_Init(&policy);
  BleConnectionPolicy_OnConnected(&policy, 4000u);
  BleConnectionPolicy_OnDisconnected(&policy);

  expect_false("disconnected never terminates",
               BleConnectionPolicy_ShouldTerminate(
                   &policy, 4000u + BLE_APP_HANDSHAKE_TIMEOUT_MS));
}

static void test_wraparound_timeout(void)
{
  BleConnectionPolicy_t policy;
  BleConnectionPolicy_Init(&policy);
  BleConnectionPolicy_OnConnected(&policy, 0xFFFFfff0u);

  expect_false("wrap before timeout",
               BleConnectionPolicy_ShouldTerminate(&policy, 0x00000010u));
  expect_true("wrap after timeout",
              BleConnectionPolicy_ShouldTerminate(
                  &policy, 0xFFFFfff0u + BLE_APP_HANDSHAKE_TIMEOUT_MS));
}

int main(void)
{
  test_idle_connection_times_out();
  test_app_activity_satisfies_handshake();
  test_handshake_pending_only_until_app_activity();
  test_terminate_request_is_one_shot();
  test_disconnect_resets_policy();
  test_wraparound_timeout();

  if (g_fails == 0) {
    printf("ble_connection_policy tests: OK\n");
    return 0;
  }
  printf("ble_connection_policy tests: %d FAIL\n", g_fails);
  return 1;
}

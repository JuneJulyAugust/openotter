#include "ble_connection_policy.h"

static int tick_reached(uint32_t now, uint32_t target)
{
  return (int32_t)(now - target) >= 0;
}

void BleConnectionPolicy_Init(BleConnectionPolicy_t *policy)
{
  if (!policy) return;
  policy->connected = 0u;
  policy->app_activity_seen = 0u;
  policy->terminate_requested = 0u;
  policy->connected_tick_ms = 0u;
}

void BleConnectionPolicy_OnConnected(BleConnectionPolicy_t *policy,
                                      uint32_t now_ms)
{
  if (!policy) return;
  policy->connected = 1u;
  policy->app_activity_seen = 0u;
  policy->terminate_requested = 0u;
  policy->connected_tick_ms = now_ms;
}

void BleConnectionPolicy_OnDisconnected(BleConnectionPolicy_t *policy)
{
  BleConnectionPolicy_Init(policy);
}

void BleConnectionPolicy_OnAppActivity(BleConnectionPolicy_t *policy)
{
  if (!policy || !policy->connected) return;
  policy->app_activity_seen = 1u;
}

int BleConnectionPolicy_HandshakePending(const BleConnectionPolicy_t *policy)
{
  return policy && policy->connected && !policy->app_activity_seen &&
         !policy->terminate_requested;
}

int BleConnectionPolicy_ShouldTerminate(const BleConnectionPolicy_t *policy,
                                        uint32_t now_ms)
{
  if (!policy || !policy->connected || policy->app_activity_seen ||
      policy->terminate_requested) {
    return 0;
  }

  return tick_reached(now_ms,
                      policy->connected_tick_ms + BLE_APP_HANDSHAKE_TIMEOUT_MS);
}

void BleConnectionPolicy_OnTerminateRequested(BleConnectionPolicy_t *policy)
{
  if (!policy) return;
  policy->terminate_requested = 1u;
}

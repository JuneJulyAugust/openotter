/* SPDX-License-Identifier: BSD-3-Clause */
#include "ble_adv_policy.h"

#include <stddef.h>

static bool tick_reached(uint32_t now_ms, uint32_t target_ms) {
  return (int32_t)(now_ms - target_ms) >= 0;
}

void BleAdvPolicy_Init(BleAdvPolicy_t *policy, uint32_t now_ms) {
  if (policy == NULL) return;
  policy->pending = 1u;
  policy->active = 0u;
  policy->fail_count = 0u;
  policy->retry_delay_ms = BLE_ADV_RETRY_MIN_MS;
  policy->retry_tick_ms = now_ms + BLE_ADV_INITIAL_DELAY_MS;
}

bool BleAdvPolicy_Due(const BleAdvPolicy_t *policy,
                      uint32_t now_ms,
                      bool connected) {
  if (policy == NULL || connected) return false;
  return policy->pending != 0u && tick_reached(now_ms, policy->retry_tick_ms);
}

void BleAdvPolicy_OnSuccess(BleAdvPolicy_t *policy) {
  if (policy == NULL) return;
  policy->pending = 0u;
  policy->active = 1u;
  policy->fail_count = 0u;
  policy->retry_delay_ms = BLE_ADV_RETRY_MIN_MS;
}

void BleAdvPolicy_OnFailure(BleAdvPolicy_t *policy, uint32_t now_ms) {
  if (policy == NULL) return;
  policy->pending = 1u;
  policy->active = 0u;
  if (policy->fail_count < 255u) {
    policy->fail_count++;
  }
  uint32_t delay = policy->retry_delay_ms;
  if (delay < BLE_ADV_RETRY_MIN_MS) {
    delay = BLE_ADV_RETRY_MIN_MS;
  }
  policy->retry_tick_ms = now_ms + delay;
  delay *= 2u;
  policy->retry_delay_ms =
      (delay > BLE_ADV_RETRY_MAX_MS) ? BLE_ADV_RETRY_MAX_MS : delay;
}

void BleAdvPolicy_OnConnected(BleAdvPolicy_t *policy) {
  if (policy == NULL) return;
  policy->pending = 0u;
  policy->active = 0u;
  policy->fail_count = 0u;
  policy->retry_delay_ms = BLE_ADV_RETRY_MIN_MS;
}

void BleAdvPolicy_OnDisconnected(BleAdvPolicy_t *policy, uint32_t now_ms) {
  if (policy == NULL) return;
  policy->pending = 1u;
  policy->active = 0u;
  policy->fail_count = 0u;
  policy->retry_delay_ms = BLE_ADV_RETRY_MIN_MS;
  policy->retry_tick_ms = now_ms + BLE_ADV_INITIAL_DELAY_MS;
}

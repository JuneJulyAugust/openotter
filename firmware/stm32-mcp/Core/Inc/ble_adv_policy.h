/* SPDX-License-Identifier: BSD-3-Clause */
#ifndef BLE_ADV_POLICY_H
#define BLE_ADV_POLICY_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BLE_ADV_INITIAL_DELAY_MS 100u
#define BLE_ADV_RETRY_MIN_MS    1000u
#define BLE_ADV_RETRY_MAX_MS    5000u
#define BLE_ADV_HEALTHCHECK_MS  15000u

typedef struct {
  uint8_t pending;
  uint8_t active;
  uint8_t fail_count;
  uint32_t retry_tick_ms;
  uint32_t retry_delay_ms;
  uint32_t healthcheck_tick_ms;
} BleAdvPolicy_t;

void BleAdvPolicy_Init(BleAdvPolicy_t *policy, uint32_t now_ms);
bool BleAdvPolicy_Due(const BleAdvPolicy_t *policy,
                      uint32_t now_ms,
                      bool connected);
bool BleAdvPolicy_HealthcheckDue(const BleAdvPolicy_t *policy,
                                  uint32_t now_ms,
                                  bool connected);
void BleAdvPolicy_OnSuccess(BleAdvPolicy_t *policy, uint32_t now_ms);
void BleAdvPolicy_OnFailure(BleAdvPolicy_t *policy, uint32_t now_ms);
void BleAdvPolicy_OnHealthcheckFailure(BleAdvPolicy_t *policy,
                                        uint32_t now_ms);
void BleAdvPolicy_OnConnected(BleAdvPolicy_t *policy);
void BleAdvPolicy_OnDisconnected(BleAdvPolicy_t *policy, uint32_t now_ms);

#ifdef __cplusplus
}
#endif

#endif /* BLE_ADV_POLICY_H */

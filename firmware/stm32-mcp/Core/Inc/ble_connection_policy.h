#ifndef BLE_CONNECTION_POLICY_H
#define BLE_CONNECTION_POLICY_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BLE_APP_HANDSHAKE_TIMEOUT_MS 10000u

typedef struct {
  uint8_t connected;
  uint8_t app_activity_seen;
  uint8_t terminate_requested;
  uint32_t connected_tick_ms;
} BleConnectionPolicy_t;

void BleConnectionPolicy_Init(BleConnectionPolicy_t *policy);
void BleConnectionPolicy_OnConnected(BleConnectionPolicy_t *policy,
                                      uint32_t now_ms);
void BleConnectionPolicy_OnDisconnected(BleConnectionPolicy_t *policy);
void BleConnectionPolicy_OnAppActivity(BleConnectionPolicy_t *policy);
int BleConnectionPolicy_HandshakePending(const BleConnectionPolicy_t *policy);
int BleConnectionPolicy_ShouldTerminate(const BleConnectionPolicy_t *policy,
                                        uint32_t now_ms);
void BleConnectionPolicy_OnTerminateRequested(BleConnectionPolicy_t *policy);

#ifdef __cplusplus
}
#endif

#endif /* BLE_CONNECTION_POLICY_H */

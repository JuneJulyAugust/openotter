#ifndef BLE_TOF_DEBUG_H
#define BLE_TOF_DEBUG_H

#include "tof_types.h"

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BLE_TOF_DEBUG_ROLE_REAR   0u
#define BLE_TOF_DEBUG_ROLE_FRONT  1u

#define BLE_TOF_DEBUG_AVAILABLE_REAR_MASK   0x01u
#define BLE_TOF_DEBUG_AVAILABLE_FRONT_MASK  0x02u
#define BLE_TOF_DEBUG_AVAILABLE_MASK        0x03u

#define BLE_TOF_DEBUG_STATUS_ROLE_MASK       0x03u
#define BLE_TOF_DEBUG_STATUS_AVAILABLE_SHIFT 4u

#define BLE_TOF_DEBUG_CONFIG_PREFIX_SIZE   ((uint16_t)sizeof(Tof_Config_t))
#define BLE_TOF_DEBUG_CONFIG_PAYLOAD_SIZE  (BLE_TOF_DEBUG_CONFIG_PREFIX_SIZE + 1u)

typedef struct {
  uint8_t pending;
  uint16_t len;
  uint8_t data[BLE_TOF_DEBUG_CONFIG_PAYLOAD_SIZE];
} BLE_TofDebugConfigQueue_t;

int BLE_TofDebugRole_IsValid(uint8_t role);
int BLE_TofDebugRoleFromConfigPayload(const uint8_t *data,
                                      uint16_t len,
                                      uint8_t *role);
uint8_t BLE_TofDebugStatusPad(uint8_t selected_role, uint8_t available_mask);
uint8_t BLE_TofDebugStatusPad_SelectedRole(uint8_t pad);
uint8_t BLE_TofDebugStatusPad_AvailableMask(uint8_t pad);
void BLE_TofDebugConfigQueue_Init(BLE_TofDebugConfigQueue_t *queue);
int BLE_TofDebugConfigQueue_HasPending(
    const BLE_TofDebugConfigQueue_t *queue);
void BLE_TofDebugConfigQueue_Clear(BLE_TofDebugConfigQueue_t *queue);
int BLE_TofDebugConfigQueue_Push(BLE_TofDebugConfigQueue_t *queue,
                                 const uint8_t *data,
                                 uint16_t len);
int BLE_TofDebugConfigQueue_Pop(BLE_TofDebugConfigQueue_t *queue,
                                uint8_t *out,
                                uint16_t out_capacity,
                                uint16_t *out_len);

#ifdef __cplusplus
}
#endif

#endif /* BLE_TOF_DEBUG_H */

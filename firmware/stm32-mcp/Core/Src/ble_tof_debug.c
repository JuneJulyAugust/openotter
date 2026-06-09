#include "ble_tof_debug.h"

#include <string.h>

int BLE_TofDebugRole_IsValid(uint8_t role)
{
  return role == BLE_TOF_DEBUG_ROLE_REAR ||
         role == BLE_TOF_DEBUG_ROLE_FRONT;
}

int BLE_TofDebugRoleFromConfigPayload(const uint8_t *data,
                                      uint16_t len,
                                      uint8_t *role)
{
  if (data == 0 || role == 0 || len < BLE_TOF_DEBUG_CONFIG_PREFIX_SIZE) {
    return -1;
  }

  if (len < BLE_TOF_DEBUG_CONFIG_PAYLOAD_SIZE) {
    *role = BLE_TOF_DEBUG_ROLE_REAR;
    return 0;
  }

  uint8_t requested_role = data[BLE_TOF_DEBUG_CONFIG_PREFIX_SIZE];
  if (!BLE_TofDebugRole_IsValid(requested_role)) {
    return -1;
  }

  *role = requested_role;
  return 0;
}

uint8_t BLE_TofDebugStatusPad(uint8_t selected_role, uint8_t available_mask)
{
  uint8_t role = BLE_TofDebugRole_IsValid(selected_role)
      ? selected_role
      : BLE_TOF_DEBUG_ROLE_REAR;
  uint8_t mask = available_mask & BLE_TOF_DEBUG_AVAILABLE_MASK;
  return (uint8_t)((mask << BLE_TOF_DEBUG_STATUS_AVAILABLE_SHIFT) |
                   (role & BLE_TOF_DEBUG_STATUS_ROLE_MASK));
}

uint8_t BLE_TofDebugStatusPad_SelectedRole(uint8_t pad)
{
  uint8_t role = pad & BLE_TOF_DEBUG_STATUS_ROLE_MASK;
  return BLE_TofDebugRole_IsValid(role) ? role : BLE_TOF_DEBUG_ROLE_REAR;
}

uint8_t BLE_TofDebugStatusPad_AvailableMask(uint8_t pad)
{
  return (uint8_t)((pad >> BLE_TOF_DEBUG_STATUS_AVAILABLE_SHIFT) &
                   BLE_TOF_DEBUG_AVAILABLE_MASK);
}

void BLE_TofDebugConfigQueue_Init(BLE_TofDebugConfigQueue_t *queue)
{
  if (!queue) return;
  memset(queue, 0, sizeof(*queue));
}

int BLE_TofDebugConfigQueue_HasPending(
    const BLE_TofDebugConfigQueue_t *queue)
{
  return queue && queue->pending;
}

void BLE_TofDebugConfigQueue_Clear(BLE_TofDebugConfigQueue_t *queue)
{
  if (!queue) return;
  queue->pending = 0u;
  queue->len = 0u;
}

int BLE_TofDebugConfigQueue_Push(BLE_TofDebugConfigQueue_t *queue,
                                 const uint8_t *data,
                                 uint16_t len)
{
  if (!queue) {
    return -1;
  }

  if (!data ||
      len < BLE_TOF_DEBUG_CONFIG_PREFIX_SIZE ||
      len > BLE_TOF_DEBUG_CONFIG_PAYLOAD_SIZE) {
    BLE_TofDebugConfigQueue_Clear(queue);
    return -1;
  }

  memcpy(queue->data, data, len);
  queue->len = len;
  queue->pending = 1u;
  return 0;
}

int BLE_TofDebugConfigQueue_Pop(BLE_TofDebugConfigQueue_t *queue,
                                uint8_t *out,
                                uint16_t out_capacity,
                                uint16_t *out_len)
{
  if (!queue || !out || !out_len || !queue->pending ||
      out_capacity < queue->len) {
    return -1;
  }

  memcpy(out, queue->data, queue->len);
  *out_len = queue->len;
  BLE_TofDebugConfigQueue_Clear(queue);
  return 0;
}

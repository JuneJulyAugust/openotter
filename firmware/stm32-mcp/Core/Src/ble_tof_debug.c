#include "ble_tof_debug.h"

int BLE_TofDebugRole_IsValid(uint8_t role)
{
  return role == BLE_TOF_DEBUG_ROLE_REAR ||
         role == BLE_TOF_DEBUG_ROLE_FRONT;
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

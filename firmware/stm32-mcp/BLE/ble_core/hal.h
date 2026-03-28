/**
 * @file  hal.h
 * @brief Compatibility shim for BlueNRG-MS core files.
 *        The ble_core/*.c files (hci_le.c, bluenrg_l2cap_aci.c) expect this
 *        header from the X-CUBE-BLE1 middleware. We redirect to the actual
 *        headers already present in our BLE/Common middleware.
 */
#ifndef __HAL_H
#define __HAL_H

#include "hal_types.h"
#include "hci_tl_io.h"

#endif /* __HAL_H */

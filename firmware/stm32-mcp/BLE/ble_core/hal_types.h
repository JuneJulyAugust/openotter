/**
 * @file  hal_types.h
 * @brief Compatibility shim for BlueNRG-MS core files.
 *        The ble_core/*.c files expect this header from the X-CUBE-BLE1 middleware.
 *        We provide the minimal type definitions they need.
 */
#ifndef __HAL_TYPES_H
#define __HAL_TYPES_H

#include <stdint.h>
#include "bluenrg_private_hal_types.h"

#ifndef NULL
#define NULL ((void *)0)
#endif

#ifndef BOOL
typedef uint8_t BOOL;
#endif

#ifndef TRUE
#define TRUE  1
#endif

#ifndef FALSE
#define FALSE 0
#endif

#endif /* __HAL_TYPES_H */

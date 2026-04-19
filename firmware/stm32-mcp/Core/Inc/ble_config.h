/**
 ******************************************************************************
 * @file    ble_config.h
 * @brief   BLE configuration for openotter STM32 MCP
 *          Derived from STM32CubeL4 P2P_LedButton config.h
 ******************************************************************************
 */

#ifndef __BLE_CONFIG_H
#define __BLE_CONFIG_H

/* This file is included by the BLE middleware as "config.h".
 * Our CMakeLists maps this via include path ordering. */

#include "stm32l4xx_ll_exti.h"
#include "stm32l4xx_ll_pwr.h"
#include "stm32l4xx_ll_rcc.h"
#include "stm32l4xx_ll_rtc.h"

#ifdef __cplusplus
extern "C" {
#endif

/*----------------------------------------------------------------------------*
 * BLE Role
 *----------------------------------------------------------------------------*/
#define CFG_BLE_HCI_STDBY 0 /* BlueNRG-MS as coprocessor */
#define BLE_CFG_PERIPHERAL 1
#define BLE_CFG_CENTRAL 0
#define GATT_CLIENT 0

/*----------------------------------------------------------------------------*
 * BLE Stack & Service Config
 *----------------------------------------------------------------------------*/
#define BLE_CFG_DATA_ROLE_MODE 0x01 /* Peripheral only */
#define BLE_CFG_SVC_MAX_NBR_CB 3    /* Max registered service handlers (FE40 + FE60) */
#define BLE_CFG_CLT_MAX_NBR_CB 0    /* No client handlers */
#define BLE_CFG_MENU_DEVICE_INFORMATION 0
#define BLE_CFG_MAX_CONNECTION 1

/*----------------------------------------------------------------------------*
 * GAP / Advertising
 *----------------------------------------------------------------------------*/
#define CFG_ADV_BD_ADDRESS 0xAABBCCDDEE01
#define CFG_FAST_CONN_ADV_INTERVAL_MIN 0x0080 /* 80ms */
#define CFG_FAST_CONN_ADV_INTERVAL_MAX 0x00A0 /* 100ms */
#define LEDBUTTON_CONN_ADV_INTERVAL_MIN CFG_FAST_CONN_ADV_INTERVAL_MIN
#define LEDBUTTON_CONN_ADV_INTERVAL_MAX CFG_FAST_CONN_ADV_INTERVAL_MAX

/*----------------------------------------------------------------------------*
 * Security (None - no pairing required)
 *----------------------------------------------------------------------------*/
#define CFG_IO_CAPABILITY 0x03   /* NoInputNoOutput */
#define CFG_MITM_PROTECTION 0x00 /* Not required */

/*----------------------------------------------------------------------------*
 * Scheduler tasks
 *----------------------------------------------------------------------------*/
#define CFG_IdleTask_HciAsynchEvt 0
#define CFG_IdleTask_TlEvt 1
#define CFG_IdleTask_StartAdv 2
#define CFG_IdleTask_Button 3
#define CFG_IdleTask_ConnDev1 4
#define CFG_IdleTask_SearchService 5
#define CFG_IdleTask_MeasReq 6
#define CFG_TASK_NBR 7
#define CFG_SCH_TASK_NBR CFG_TASK_NBR

/* Scheduler events */
#define CFG_IdleEvt_HciCmdEvtResp 0
#define CFG_EVT_NBR 1
#define CFG_SCH_EVT_NBR CFG_EVT_NBR

/*----------------------------------------------------------------------------*
 * Timer Server - uses RTC wakeup
 *----------------------------------------------------------------------------*/
#define CFG_TimProcID_isr 0

/* Timer Server Prescaling (based on LSI 32kHz)
 * CFG_RTCCLK_DIVIDER_CONF=0: custom config, tick = ~61us */
#define CFG_RTCCLK_DIVIDER_CONF 0
#define CFG_RTC_WUCKSEL_DIVIDER 3
#define CFG_RTC_ASYNCH_PRESCALER 1
#define CFG_RTC_SYNCH_PRESCALER 0x7FFF

#define CFG_HW_TS_NVICRTCWakeUpPRIO 3
#define CFG_HW_TS_NVIC_RTC_WAKEUP_SUBPRIO 0
#define CFG_HW_TS_NVIC_RTC_WAKEUP_IT_PREEMPTPRIO CFG_HW_TS_NVICRTCWakeUpPRIO
#define CFG_HW_TS_NVIC_RTC_WAKEUP_IT_SUBPRIO CFG_HW_TS_NVIC_RTC_WAKEUP_SUBPRIO
#define CFG_HW_TS_MAX_NBR_CONCURRENT_TIMER 4

#define CFG_HW_TS_RTC_HANDLER_MAX_DELAY 16
#define CFG_HW_TS_RTC_WAKEUP_HANDLER_ID RTC_WKUP_IRQn
#define CFG_HW_TS_USE_PRIMASK_AS_CRITICAL_SECTION 1

/* Timer Server tick value in µs (LSI 32kHz, prescaler=1 → 1/16000 s ≈ 61µs) */
#define CFG_TS_TICK_VAL 61

/*----------------------------------------------------------------------------*
 * Low Power Manager
 *----------------------------------------------------------------------------*/
#define CFG_LPM_App 0
#define LPM_SPI_TX_Id 1
#define LPM_SPI_RX_Id 2
#define CFG_LPM_HCI_AsynchEvt 3

/* Stop/Standby mode selectors */
#define CFG_StopMode0 0x00
#define CFG_StopMode1 0x01
#define CFG_StopMode2 0x02
#define CFG_Standby 0x03

/*----------------------------------------------------------------------------*
 * Debug
 *----------------------------------------------------------------------------*/
#define CFG_DEBUGGER_SUPPORTED 1
#define CFG_DEBUG_TRACE                                                        \
  0 /* Disable debug trace (avoids DBG_TRACE_DBG dependency) */
#define CFG_DEBUG_BLE_TRACE 0

/*----------------------------------------------------------------------------*
 * Transport Layer Buffer
 *----------------------------------------------------------------------------*/
#define CFG_TLBLE_MOST_EVENT_PAYLOAD_SIZE 255 /* Max HCI event payload */
#define CFG_TLBLE_EVT_QUEUE_LENGTH 5

/*----------------------------------------------------------------------------*
 * SPI Timing (from P2P_LedButton reference)
 * Based on LSI 32kHz, tick ~54us
 *----------------------------------------------------------------------------*/
#define SPI_END_RECEIVE_FIX 1
#define SPI_TX_TIMEOUT 6
#define SPI_END_RECEIVE_FIX_TIMEOUT 2
#define SPI_FIFO_RX_DEPTH 4
#define BLUENRG_HOLD_TIME_IN_RESET 28
#define CS_PULSE_625NS_NBR_CYCLES_REQ 52

/*----------------------------------------------------------------------------*
 * UART (for debug trace output via ST-LINK VCP)
 *----------------------------------------------------------------------------*/
#define CFG_HW_UART1_SUPPORTED 1
#define CFG_HW_UART2 0

#define CFG_HW_UART1_PREEMPTPRIORITY 0x0F
#define CFG_HW_UART1_SUBPRIORITY 0

#define CFG_HW_UART1_BAUDRATE 115200
#define CFG_HW_UART1_WORDLENGTH UART_WORDLENGTH_8B
#define CFG_HW_UART1_STOPBITS UART_STOPBITS_1
#define CFG_HW_UART1_PARITY UART_PARITY_NONE
#define CFG_HW_UART1_HWFLOWCTL UART_HWCONTROL_NONE
#define CFG_HW_UART1_MODE UART_MODE_TX_RX
#define CFG_HW_UART1_ADVFEATUREINIT UART_ADVFEATURE_NO_INIT

/* UART1 TX: PB6 */
#define CFG_HW_UART1_TX_PORT_CLK_ENABLE __HAL_RCC_GPIOB_CLK_ENABLE
#define CFG_HW_UART1_TX_PORT GPIOB
#define CFG_HW_UART1_TX_PIN GPIO_PIN_6
#define CFG_HW_UART1_TX_MODE GPIO_MODE_AF_PP
#define CFG_HW_UART1_TX_PULL GPIO_NOPULL
#define CFG_HW_UART1_TX_SPEED GPIO_SPEED_HIGH
#define CFG_HW_UART1_TX_ALTERNATE GPIO_AF7_USART1

/* UART1 RX: PB7 */
#define CFG_HW_UART1_RX_PORT_CLK_ENABLE __HAL_RCC_GPIOB_CLK_ENABLE
#define CFG_HW_UART1_RX_PORT GPIOB
#define CFG_HW_UART1_RX_PIN GPIO_PIN_7
#define CFG_HW_UART1_RX_MODE GPIO_MODE_AF_PP
#define CFG_HW_UART1_RX_PULL GPIO_NOPULL
#define CFG_HW_UART1_RX_SPEED GPIO_SPEED_HIGH
#define CFG_HW_UART1_RX_ALTERNATE GPIO_AF7_USART1

/*----------------------------------------------------------------------------*
 * Compiler Helpers
 *----------------------------------------------------------------------------*/
#if defined(__CC_ARM)
#define USED __attribute__((used))
#elif defined(__ICCARM__)
#define USED __root
#elif defined(__GNUC__)
#define USED __attribute__((used))
#endif

#ifdef __cplusplus
}
#endif

#endif /* __BLE_CONFIG_H */

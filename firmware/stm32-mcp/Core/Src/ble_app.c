/**
 ******************************************************************************
 * @file    ble_app.c
 * @brief   OpenOtter BLE Application
 *
 *          Architecture:
 *          - Uses BlueNRG-MS stack via SPI3 (SPBTLE-RF module)
 *          - Registers a custom GATT service with a Write characteristic
 *          - On write: extracts steering_us and throttle_us (int16_t each)
 *          - Applies values to TIM3 CH4 (steering) and CH1 (throttle)
 *          - Safety timeout: reverts to neutral after 1.5s without commands
 *
 *          Based on STM32CubeL4 P2P_LedButton example, heavily simplified.
 ******************************************************************************
 */

/* Includes ------------------------------------------------------------------*/
#include "ble_app.h"

#include "common.h"
#include "debug.h"
#include "hw.h"
#include "scheduler.h"
#include "lpm.h"
#include "tl_types.h"
#include "tl_ble_hci.h"
#include "tl_ble_reassembly.h"
#include "svc_ctl.h"
#include "ble_lib.h"
#include "blesvc.h"

#include <string.h>

/* Private types -------------------------------------------------------------*/

/** BLE Application context */
typedef struct {
  TIM_HandleTypeDef *htim;
  uint16_t svcHandle;
  uint16_t cmdCharHandle;
  uint16_t statusCharHandle;
  uint16_t safetyCharHandle;
  uint16_t modeCharHandle;
  uint16_t connectionHandle;
  volatile uint32_t lastCommandTick;
  volatile uint8_t  isConnected;
  volatile uint8_t  safetyTriggered;
  int16_t currentSteering;
  int16_t currentThrottle;

  /* From the most recent 0xFE41 write. */
  int16_t desiredSteeringUs;
  int16_t desiredThrottleUs;
  int16_t reportedVelocityMmPerS;

  OpenOtterMode_t mode;
} BLE_AppContext_t;

/* Private variables ---------------------------------------------------------*/
static BLE_AppContext_t bleCtx;
RTC_HandleTypeDef hrtc_ble;

/* HCI transport layer buffers */
#define POOL_SIZE                                                              \
  (CFG_TLBLE_EVT_QUEUE_LENGTH *                                                \
   (sizeof(TL_PacketHeader_t) + TL_BLE_EVENT_FRAME_SIZE))
static TL_CmdPacket_t HciCmdBuffer;
static uint8_t HciEvtPool[POOL_SIZE];

/* Forward declarations ------------------------------------------------------*/
static void BLE_InitStack(void);
static void BLE_InitGATTService(void);
static void BLE_StartAdvertising(void);
static void BLE_ApplyPWM(int16_t steering_us, int16_t throttle_us);
static int16_t BLE_ClampPulse(int16_t pulse_us);
static SVCCTL_EvtAckStatus_t BLE_EventHandler(void *event);

static void BLE_InitRTC(void);
static void BLE_InitLPM(void);

/* ---- Scheduler task callbacks ---- */
static void BLE_HciUserEvtTask(void);
static void BLE_TlEvtTask(void);
static void BLE_AdvTask(void);

/*============================================================================*/
/*  PUBLIC API                                                                */
/*============================================================================*/

int BLE_App_Init(TIM_HandleTypeDef *htim) {
  memset(&bleCtx, 0, sizeof(bleCtx));
  bleCtx.htim = htim;
  bleCtx.currentSteering = PWM_NEUTRAL_US;
  bleCtx.currentThrottle = PWM_NEUTRAL_US;
  bleCtx.lastCommandTick = HAL_GetTick();
  bleCtx.mode = OPENOTTER_MODE_DRIVE;

  BLE_InitLPM();
  BLE_InitRTC();
  HW_TS_Init(hw_ts_InitMode_Full, &hrtc_ble);

  SCH_RegTask(CFG_IdleTask_HciAsynchEvt, BLE_HciUserEvtTask);
  SCH_RegTask(CFG_IdleTask_TlEvt, BLE_TlEvtTask);
  SCH_RegTask(CFG_IdleTask_StartAdv, BLE_AdvTask);

  BLE_InitStack();
  BLE_InitGATTService();
  BLE_ApplyPWM(PWM_NEUTRAL_US, PWM_NEUTRAL_US);
  BLE_StartAdvertising();

  return 0;
}

void BLE_App_Process(void) {
  /* Run the scheduler (processes pending BLE events) */
  SCH_Run();

  /* Safety timeout check */
  if (bleCtx.isConnected) {
    uint32_t elapsed = HAL_GetTick() - bleCtx.lastCommandTick;
    if (elapsed > BLE_SAFETY_TIMEOUT_MS) {
      if (!bleCtx.safetyTriggered) {
        BLE_ApplyPWM(PWM_NEUTRAL_US, PWM_NEUTRAL_US);
        bleCtx.safetyTriggered = 1;
      }
    }
  }
}

uint32_t BLE_App_GetLastCommandTime(void) { return bleCtx.lastCommandTick; }

OpenOtterMode_t BLE_App_GetMode(void) { return bleCtx.mode; }

int BLE_App_IsConnected(void) { return bleCtx.isConnected; }

/*============================================================================*/
/*  BLE STACK INITIALIZATION                                                  */
/*============================================================================*/

static void BLE_InitStack(void) {
  /* Initialize HCI transport layer — this inits SPI3, resets BlueNRG,
   * and waits for the reset event from the module. Must happen before
   * any HCI commands (i.e. before SVCCTL_Init). */
  TL_BLE_HCI_Init(TL_BLE_HCI_InitFull, &HciCmdBuffer, HciEvtPool, POOL_SIZE);

  SVCCTL_Init();
}

static void BLE_InitGATTService(void) {
  uint16_t uuid;
  tBleStatus ret;

  /* Register this module's event handler */
  SVCCTL_RegisterSvcHandler(BLE_EventHandler);

  /*
   * Add Custom Control Service
   * Max_Attribute_Records = 1 (service) + 2 (cmd char) + 2 (status char)
   *                       + 1 (CCCD for notify) = 6
   */
  uuid = OPENOTTER_CONTROL_SVC_UUID;
  ret = aci_gatt_add_serv(UUID_TYPE_16, (const uint8_t *)&uuid, PRIMARY_SERVICE,
                          6, &bleCtx.svcHandle);
  if (ret != BLE_STATUS_SUCCESS) {
    /* Service creation failed — halt */
    return;
  }

  /*
   * Add Command Characteristic (Write Without Response)
   * Payload: 4 bytes = [int16_t steering_us, int16_t throttle_us]
   */
  uuid = OPENOTTER_COMMAND_CHAR_UUID;
  ret = aci_gatt_add_char(bleCtx.svcHandle, UUID_TYPE_16,
                          (const uint8_t *)&uuid,
                          sizeof(BLE_CommandPayload_t), /* 6 bytes */
                          CHAR_PROP_WRITE_WITHOUT_RESP | CHAR_PROP_WRITE,
                          ATTR_PERMISSION_NONE, GATT_NOTIFY_ATTRIBUTE_WRITE,
                          10,
                          0,
                          &bleCtx.cmdCharHandle);

  /*
   * Add Status Characteristic (Notify)
   * We can send status/heartbeat back to iOS
   */
  uuid = OPENOTTER_STATUS_CHAR_UUID;
  ret = aci_gatt_add_char(bleCtx.svcHandle, UUID_TYPE_16,
                          (const uint8_t *)&uuid, 4, /* max value length */
                          CHAR_PROP_NOTIFY | CHAR_PROP_READ,
                          ATTR_PERMISSION_NONE, GATT_NOTIFY_ATTRIBUTE_WRITE, 10,
                          0, &bleCtx.statusCharHandle);

  (void)ret; /* Suppress unused warning in release */
}

static void BLE_StartAdvertising(void) {
  if (bleCtx.isConnected)
    return;

  const char ad_name[] = {AD_TYPE_COMPLETE_LOCAL_NAME,
                          'O',
                          'P',
                          'E',
                          'N',
                          'O',
                          'T',
                          'T',
                          'E',
                          'R',
                          '-',
                          'M',
                          'C',
                          'P'};

  const uint8_t svc_uuid_list[] = {AD_TYPE_16_BIT_SERV_UUID_CMPLT_LIST,
                                   (uint8_t)(OPENOTTER_CONTROL_SVC_UUID & 0xFF),
                                   (uint8_t)(OPENOTTER_CONTROL_SVC_UUID >> 8)};

  tBleStatus ret = aci_gap_set_discoverable(
      ADV_IND, CFG_FAST_CONN_ADV_INTERVAL_MIN, CFG_FAST_CONN_ADV_INTERVAL_MAX,
      PUBLIC_ADDR, NO_WHITE_LIST_USE, sizeof(ad_name), ad_name,
      sizeof(svc_uuid_list), (uint8_t *)svc_uuid_list, 0, 0);

  if (ret != BLE_STATUS_SUCCESS) {
    /* Retry via scheduler if the stack wasn't ready yet */
    SCH_SetTask(CFG_IdleTask_StartAdv);
  }
}

/*============================================================================*/
/*  GATT EVENT HANDLER                                                        */
/*============================================================================*/

static SVCCTL_EvtAckStatus_t BLE_EventHandler(void *Event) {
  SVCCTL_EvtAckStatus_t return_value = SVCCTL_EvtNotAck;
  hci_event_pckt *event_pckt =
      (hci_event_pckt *)(((hci_uart_pckt *)Event)->data);

  switch (event_pckt->evt) {
  case EVT_VENDOR: {
    evt_blue_aci *blue_evt = (evt_blue_aci *)event_pckt->data;
    switch (blue_evt->ecode) {
    case EVT_BLUE_GATT_ATTRIBUTE_MODIFIED: {
      evt_gatt_attr_modified *attr_mod =
          (evt_gatt_attr_modified *)blue_evt->data;

      /* Check if this is a write to our Command characteristic value */
      if (attr_mod->attr_handle == (bleCtx.cmdCharHandle + 1)) {
        return_value = SVCCTL_EvtAck;

        if (attr_mod->data_length >= (uint16_t)sizeof(BLE_CommandPayload_t)) {
          BLE_CommandPayload_t cmd;
          memcpy(&cmd, attr_mod->att_data, sizeof(cmd));
          bleCtx.desiredSteeringUs      = cmd.steering_us;
          bleCtx.desiredThrottleUs      = cmd.throttle_us;
          bleCtx.reportedVelocityMmPerS = cmd.velocity_mm_per_s;

          BLE_ApplyPWM(cmd.steering_us, cmd.throttle_us);

          bleCtx.lastCommandTick = HAL_GetTick();
          bleCtx.safetyTriggered = 0;
        }
      }
      break;
    }
    default:
      break;
    }
    break;
  }
  default:
    break;
  }

  return return_value;
}

/*============================================================================*/
/*  GAP EVENT HANDLER (called by svc_ctl for connection/disconnection)        */
/*============================================================================*/

/**
 * @brief  Called by SVCCTL for GAP-level events (connect/disconnect).
 *         This overrides the __weak function in svc_ctl.c.
 */
void SVCCTL_App_Notification(void *pckt) {
  hci_event_pckt *event_pckt = (hci_event_pckt *)((hci_uart_pckt *)pckt)->data;

  switch (event_pckt->evt) {
  case EVT_DISCONN_COMPLETE: {
    bleCtx.isConnected = 0;
    bleCtx.connectionHandle = 0;
    BLE_ApplyPWM(PWM_NEUTRAL_US, PWM_NEUTRAL_US);
    /* Defer re-advertising to the scheduler — calling
     * aci_gap_set_discoverable from inside an HCI event
     * callback can fail because the command channel is busy. */
    SCH_SetTask(CFG_IdleTask_StartAdv);
    break;
  }
  case EVT_LE_META_EVENT: {
    evt_le_meta_event *meta = (evt_le_meta_event *)event_pckt->data;
    if (meta->subevent == EVT_LE_CONN_COMPLETE) {
      evt_le_connection_complete *conn =
          (evt_le_connection_complete *)meta->data;
      bleCtx.connectionHandle = conn->handle;
      bleCtx.isConnected = 1;
      bleCtx.lastCommandTick = HAL_GetTick();
      bleCtx.safetyTriggered = 0;
    }
    break;
  }
  default:
    break;
  }
}

/*============================================================================*/
/*  PWM OUTPUT                                                                */
/*============================================================================*/

static int16_t BLE_ClampPulse(int16_t pulse_us) {
  if (pulse_us < PWM_MIN_US)
    return PWM_MIN_US;
  if (pulse_us > PWM_MAX_US)
    return PWM_MAX_US;
  return pulse_us;
}

/**
 * @brief  Apply steering and throttle pulse widths to TIM3.
 *         TIM3 config: PSC=79, ARR=19999 → 1 tick = 1µs, period = 20ms
 *         So CCR value in ticks == pulse width in µs.
 */
static void BLE_ApplyPWM(int16_t steering_us, int16_t throttle_us) {
  if (!bleCtx.htim)
    return;

  int16_t s = BLE_ClampPulse(steering_us);
  int16_t t = BLE_ClampPulse(throttle_us);

  bleCtx.currentSteering = s;
  bleCtx.currentThrottle = t;

  /* TIM3_CH4 = PB1 = steering servo */
  __HAL_TIM_SET_COMPARE(bleCtx.htim, TIM_CHANNEL_4, (uint32_t)s);
  /* TIM3_CH1 = PB4 = throttle ESC */
  __HAL_TIM_SET_COMPARE(bleCtx.htim, TIM_CHANNEL_1, (uint32_t)t);
}

/*============================================================================*/
/*  SCHEDULER TASK CALLBACKS                                                  */
/*============================================================================*/

static void BLE_HciUserEvtTask(void) { TL_BLE_HCI_UserEvtProc(); }

static void BLE_TlEvtTask(void) { TL_BLE_R_EvtProc(); }

static void BLE_AdvTask(void) { BLE_StartAdvertising(); }

/*============================================================================*/
/*  RTC & LPM INITIALIZATION (required by BLE middleware)                     */
/*============================================================================*/

static void BLE_InitRTC(void) {
  __HAL_RCC_LSI_ENABLE();

  HAL_PWR_EnableBkUpAccess();
  HAL_PWR_EnableBkUpAccess();

  __HAL_RCC_RTC_CONFIG(RCC_RTCCLKSOURCE_LSI);
  __HAL_RCC_RTC_ENABLE();

  hrtc_ble.Instance = RTC;
  HAL_RTCEx_EnableBypassShadow(&hrtc_ble);

  hrtc_ble.Init.AsynchPrediv = CFG_RTC_ASYNCH_PRESCALER;
  hrtc_ble.Init.SynchPrediv = CFG_RTC_SYNCH_PRESCALER;
  hrtc_ble.Init.OutPut = RTC_OUTPUT_DISABLE;
  hrtc_ble.Init.HourFormat = RTC_HOURFORMAT_24;
  hrtc_ble.Init.OutPutPolarity = RTC_OUTPUT_POLARITY_HIGH;
  HAL_RTC_Init(&hrtc_ble);

  __HAL_RTC_WRITEPROTECTION_DISABLE(&hrtc_ble);
  LL_RTC_WAKEUP_SetClock(hrtc_ble.Instance, CFG_RTC_WUCKSEL_DIVIDER);

  while (__HAL_RCC_GET_FLAG(RCC_FLAG_LSIRDY) == 0) { /* wait */
  }
}

static void BLE_InitLPM(void) {
  /* Disable standby mode — we want to stay running */
  LPM_SetOffMode(CFG_LPM_App, LPM_OffMode_Dis);
}

/*============================================================================*/
/*  OVERLOADED WEAK FUNCTIONS (required by BLE middleware) */
/*============================================================================*/

/**
 * @brief  Called by the BLE middleware scheduler when idle.
 *         We do NOT enter low power — we return immediately.
 */
void SCH_Idle(void) { /* No low power mode — just return to the main loop */ }

/**
 * @brief  Timer server notification callback.
 */
void HW_TS_RTC_Int_AppNot(uint32_t TimerProcessID, uint8_t TimerID,
                          HW_TS_pTimerCb_t pTimerCallBack) {
  /* Always call the callback directly (no RTOS) */
  pTimerCallBack();
}

/**
 * @brief  Override HCI status notification so we don't need the
 *         full P2P scheduler task pausing logic.
 */
void TL_BLE_HCI_StatusNot(TL_BLE_HCI_CmdStatus_t status) {
  switch (status) {
  case TL_BLE_HCI_CmdBusy:
    SCH_PauseTask(CFG_IdleTask_StartAdv);
    SCH_PauseTask(CFG_IdleTask_HciAsynchEvt);
    break;
  case TL_BLE_HCI_CmdAvailable:
    SCH_ResumeTask(CFG_IdleTask_StartAdv);
    SCH_ResumeTask(CFG_IdleTask_HciAsynchEvt);
    break;
  default:
    break;
  }
}

/**
 * @brief  GATT services init — called by SVCCTL_Init().
 *         We handle our own service registration in BLE_InitGATTService(),
 *         but the middleware calls this weak function for additional services.
 */
void BLESVC_InitCustomSvc(void) {
  /* Our service is initialized after SVCCTL_Init() in BLE_App_Init() */
}

/**
 * @brief  GPIO EXTI callback — routes BLE SPI IRQ to the BlueNRG driver.
 *         This must be called from the stm32l4xx_it.c EXTI9_5_IRQHandler.
 */
void HAL_GPIO_EXTI_Callback(uint16_t GPIO_Pin) {
  if (GPIO_Pin == GPIO_PIN_6) { /* PE6 = SPBTLE-RF IRQ */
    HW_BNRG_SpiIrqCb();
  }
}

/**
 * @brief  RTC Wakeup IRQ - route to Timer Server
 */
void HAL_RTCEx_WakeUpTimerEventCallback(RTC_HandleTypeDef *hrtc) {
  (void)hrtc;
  HW_TS_RTC_Wakeup_Handler();
}

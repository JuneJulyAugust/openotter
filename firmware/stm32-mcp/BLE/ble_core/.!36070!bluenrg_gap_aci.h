/******************** (C) COPYRIGHT 2014 STMicroelectronics ********************
* File Name          : bluenrg_gap_aci.h
* Author             : AMS - AAS
* Version            : V1.0.0
* Date               : 26-Jun-2014
* Description        : Header file with GAP commands for BlueNRG
********************************************************************************
* This software is licensed under terms that can be found in the LICENSE file
* in the root directory of this software component.
* If no LICENSE file comes with this software, it is provided AS-IS.
*******************************************************************************/

#ifndef __BLUENRG_GAP_ACI_H__
#define __BLUENRG_GAP_ACI_H__

/**
 *@addtogroup GAP GAP
 *@brief GAP layer.
 *@{
 */

/**
 *@defgroup GAP_Functions GAP functions
 *@brief API for GAP layer.
 *@{
 */

#if BLUENRG_MS
///@cond BLUENRG_MS
/**
  * @brief  Initialize the GAP layer.
  * @note   Register the GAP service with the GATT. 
  *         All the standard GAP characteristics will also be added:
  *         @li Device Name
  *         @li Appearance
  *         @li Peripheral Preferred Connection Parameters (peripheral role only)
  *         @code
  *
  *           tBleStatus ret;
  *           uint16_t service_handle, dev_name_char_handle, appearance_char_handle;
  *
  *           ret = aci_gap_init(1, 0, 0x07, &service_handle, &dev_name_char_handle, &appearance_char_handle);
  *           if(ret){
  *             PRINTF("GAP_Init failed.\n");
  *             reboot();    
  *           }  
  *           const char *name = "BlueNRG";  
  *           ret = aci_gatt_update_char_value(service_handle, dev_name_char_handle, 0, strlen(name), (uint8_t *)name);        
  *           if(ret){
  *             PRINTF("aci_gatt_update_char_value failed.\n");
  *           }  
  *         @endcode
  * @param       role     Bitmap of allowed roles: see @ref gap_roles "GAP roles".
  * @param       privacy_enabled     Enable (1) or disable (0) privacy.
  * @param       device_name_char_len Length of the device name characteristic
  * @param[out]  service_handle  Handle of the GAP service.
  * @param[out]  dev_name_char_handle  Device Name Characteristic handle
  * @param[out]  appearance_char_handle Appearance Characteristic handle
  * @retval tBleStatus Value indicating success or error code.
  */
tBleStatus aci_gap_init(uint8_t role, uint8_t privacy_enabled,
                        uint8_t device_name_char_len,
                        uint16_t* service_handle,
                        uint16_t* dev_name_char_handle,
                        uint16_t* appearance_char_handle);
///@endcond
#else
///@cond BLUENRG
/**
  * @brief  Initialize the GAP layer.
  * @note   Register the GAP service with the GATT.
  *         All the standard GAP characteristics will also be added:
  *         @li Device Name
  *         @li Appearance
  *         @li Peripheral Privacy Flag (peripheral role only)
  *         @li Reconnection Address (peripheral role only)
  *         @li Peripheral Preferred Connection Parameters (peripheral role only)
  *         @code
  *
  *           tBleStatus ret;
  *           uint16_t service_handle, dev_name_char_handle, appearance_char_handle;
  *
  *           ret = aci_gap_init(1, &service_handle, &dev_name_char_handle, &appearance_char_handle);
  *           if(ret){
  *             PRINTF("GAP_Init failed.\n");
  *             reboot();    
  *           }  
  *           const char *name = "BlueNRG";  
  *           ret = aci_gatt_update_char_value(service_handle, dev_name_char_handle, 0, strlen(name), (uint8_t *)name);        
  *           if(ret){
  *             PRINTF("aci_gatt_update_char_value failed.\n");
  *           }  
  *         @endcode
  * @param       role     One of the allowed roles: @ref GAP_PERIPHERAL_ROLE or @ref GAP_CENTRAL_ROLE. See @ref gap_roles "GAP roles".
  * @param[out]  service_handle  Handle of the GAP service.
  * @param[out]  dev_name_char_handle  Device Name Characteristic handle
  * @param[out]  appearance_char_handle Appearance Characteristic handle
  * @retval tBleStatus Value indicating success or error code.
  */
tBleStatus aci_gap_init(uint8_t role,
                 uint16_t* service_handle,
                 uint16_t* dev_name_char_handle,
                 uint16_t* appearance_char_handle);
///@endcond
#endif

/**
  * @brief   Set the Device in non-discoverable mode.
  * @note    This command will disable the LL advertising.
  * @retval  tBleStatus Value indicating success or error code.
  */
tBleStatus aci_gap_set_non_discoverable(void);

/**
 * @brief  Put the device in limited discoverable mode
 *         (as defined in GAP specification volume 3, section 9.2.3).
 * @note    The device will be discoverable for TGAP (lim_adv_timeout) = 180 seconds.
 *          The advertising can be disabled at any time by issuing
 *          aci_gap_set_non_discoverable() command.
 *          The AdvIntervMin and AdvIntervMax parameters are optional. If both
 *          are set to 0, the GAP will use default values (250 ms and 500 ms respectively).
 *          Host can set the Local Name, a Service UUID list and the Slave Connection
 *          Minimum and Maximum. If provided, these data will be inserted into the
 *          advertising packet payload as AD data. These parameters are optional
 *          in this command. These values can be also set using aci_gap_update_adv_data()
 *          separately.
 *          The total size of data in advertising packet cannot exceed 31 bytes.
 *          With this command, the BLE Stack will also add automatically the following
 *          standard AD types:
 *          @li AD Flags
 *          @li TX Power Level
 *
 *          When advertising timeout happens (i.e. limited discovery period has elapsed), controller generates
 *          @ref EVT_BLUE_GAP_LIMITED_DISCOVERABLE event.
 *
 *          Example:
 * @code
 *
 *              #define  ADV_INTERVAL_MIN_MS  100
 *              #define  ADV_INTERVAL_MAX_MS  200
 *
 *              tBleStatus ret;
 *
 *              const char local_name[] = {AD_TYPE_COMPLETE_LOCAL_NAME,'B','l','u','e','N','R','G'};
 *              const uint8_t serviceUUIDList[] = {AD_TYPE_16_BIT_SERV_UUID,0x34,0x12};
 *
 *              ret = aci_gap_set_limited_discoverable(ADV_IND, (ADV_INTERVAL_MIN_MS*1000)/0.625,
 *                                                     (ADV_INTERVAL_MAX_MS*1000)/0.625,
 *                                                     STATIC_RANDOM_ADDR, NO_WHITE_LIST_USE,
 *                                                     sizeof(local_name), local_name,
 *                                                     sizeof(serviceUUIDList), serviceUUIDList,
 *                                                     0, 0);
 * @endcode
 *
 * @param       AdvType     One of the advertising types:
 *               @arg @ref ADV_IND Connectable undirected advertising
 *               @arg @ref ADV_SCAN_IND Scannable undirected advertising
 *               @arg @ref ADV_NONCONN_IND Non connectable undirected advertising
 * @param       AdvIntervMin    Minimum advertising interval.
 *                  Range: 0x0020 to 0x4000
 *                  Default: 250 ms
 *                  Time = N * 0.625 msec
 *                  Time Range: 20 ms to 10.24 sec (minimum 100 ms for ADV_SCAN_IND or ADV_NONCONN_IND).
 * @param       AdvIntervMax    Maximum advertising interval.
 *                 Range: 0x0020 to 0x4000
 *                 Default: 500 ms
 *                 Time = N * 0.625 msec
 *                 Time Range: 20 ms to 10.24 sec  (minimum 100 ms for ADV_SCAN_IND or ADV_NONCONN_IND).
 * @param       OwnAddrType     Type of our address used during advertising
 *                              (@ref PUBLIC_ADDR,@ref STATIC_RANDOM_ADDR).
 * @param       AdvFilterPolicy  Filter policy:
 *                               @arg NO_WHITE_LIST_USE
 *                               @arg WHITE_LIST_FOR_ONLY_SCAN
 *                               @arg WHITE_LIST_FOR_ONLY_CONN
 *                               @arg WHITE_LIST_FOR_ALL
 * @param  LocalNameLen  Length of LocalName array.
 * @param  LocalName  Array containing the Local Name AD data. First byte is the AD type:
 *                       @ref AD_TYPE_SHORTENED_LOCAL_NAME or @ref AD_TYPE_COMPLETE_LOCAL_NAME.
 * @param  ServiceUUIDLen Length of ServiceUUIDList array.
 * @param  ServiceUUIDList  This is the list of the UUIDs AD Types as defined in Volume 3,
 *                Section 11.1.1 of GAP Specification. First byte is the AD Type.
 *                @arg @ref AD_TYPE_16_BIT_SERV_UUID
 *                @arg @ref AD_TYPE_16_BIT_SERV_UUID_CMPLT_LIST
 *                @arg @ref AD_TYPE_128_BIT_SERV_UUID
 *                @arg @ref AD_TYPE_128_BIT_SERV_UUID_CMPLT_LIST
 * @param  SlaveConnIntervMin Slave connection interval minimum value suggested by Peripheral.
 *                If SlaveConnIntervMin and SlaveConnIntervMax are not 0x0000,
 *                Slave Connection Interval Range AD structure will be added in advertising
 *                data.
 *                Connection interval is defined in the following manner:
 *                connIntervalmin = Slave_Conn_Interval_Min x 1.25ms
 *                Slave_Conn_Interval_Min range: 0x0006 to 0x0C80
 *                Value of 0xFFFF indicates no specific minimum.
 * @param  SlaveConnIntervMax Slave connection interval maximum value suggested by Peripheral.
 *                If SlaveConnIntervMin and SlaveConnIntervMax are not 0x0000,
 *                Slave Connection Interval Range AD structure will be added in advertising
 *                data.
 *                ConnIntervalmax = Slave_Conn_Interval_Max x 1.25ms
 *                Slave_Conn_Interval_Max range: 0x0006 to 0x0C80
 *                Slave_ Conn_Interval_Max shall be equal to or greater than the Slave_Conn_Interval_Min.
 *                Value of 0xFFFF indicates no specific maximum.
 *
 * @retval tBleStatus Value indicating success or error code.
 */
tBleStatus aci_gap_set_limited_discoverable(uint8_t AdvType, uint16_t AdvIntervMin, uint16_t AdvIntervMax,
              uint8_t OwnAddrType, uint8_t AdvFilterPolicy, uint8_t LocalNameLen,
              const char *LocalName, uint8_t ServiceUUIDLen, uint8_t* ServiceUUIDList,
              uint16_t SlaveConnIntervMin, uint16_t SlaveConnIntervMax);
/**
 * @brief Put the Device in general discoverable mode (as defined in GAP specification volume 3, section 9.2.4).
 * @note  The device will be discoverable until the Host issue Aci_Gap_Set_Non_Discoverable command.
 *       The Adv_Interval_Min and Adv_Interval_Max parameters are optional. If both are set to 0, the GAP uses
 *      the default values for advertising intervals
 *        @cond BLUENRG
 *        :\n
 *        @li Adv_Interval_Min = 1.28 s
 *        @li Adv_Interval_Max = 2.56 s
 *        @endcond
 *        @cond BLUENRG_MS
 *        When using connectable undirected advertising events:\n
 *        @li Adv_Interval_Min = 30 ms
 *        @li Adv_Interval_Max = 60 ms
 *        \nWhen using non-connectable advertising events or scannable undirected advertising events:\n
 *        @li Adv_Interval_Min = 100 ms
 *        @li Adv_Interval_Max = 150 ms
 *        @endcond
 *       Host can set the Local Name, a Service UUID list and the Slave Connection Interval Range. If provided,
 *       these data will be inserted into the advertising packet payload as AD data. These parameters are optional
 *       in this command. These values can be also set using aci_gap_update_adv_data() separately.
 *       The total size of data in advertising packet cannot exceed 31 bytes.
 *       With this command, the BLE Stack will also add automatically the following standard AD types:
 *       @li AD Flags
 *       @li TX Power Level
 *
 *       Usage example:
 *
 *       @code
 *
 *              #define  ADV_INTERVAL_MIN_MS  800
 *              #define  ADV_INTERVAL_MAX_MS  900
 *              #define  CONN_INTERVAL_MIN_MS 100
 *              #define  CONN_INTERVAL_MAX_MS 300
 *
 *              tBleStatus ret;
 *
 *              const char local_name[] = {AD_TYPE_COMPLETE_LOCAL_NAME,'B','l','u','e','N','R','G'};
 *              const uint8_t serviceUUIDList[] = {AD_TYPE_16_BIT_SERV_UUID,0x34,0x12};
 *
 *              ret = aci_gap_set_discoverable(ADV_IND, (ADV_INTERVAL_MIN_MS*1000)/625,
 *                                                     (ADV_INTERVAL_MAX_MS*1000)/625,
 *                                                     STATIC_RANDOM_ADDR, NO_WHITE_LIST_USE,
 *                                                     sizeof(local_name), local_name,
 *                                                     0, NULL,
 *                                                     (CONN_INTERVAL_MIN_MS*1000)/1250,
 *                                                     (CONN_INTERVAL_MAX_MS*1000)/1250);
 *       @endcode
 *
 * @param AdvType One of the advertising types:
 *                @arg @ref ADV_IND Connectable undirected advertising
 *                @arg @ref ADV_SCAN_IND Scannable undirected advertising
 *                @arg @ref ADV_NONCONN_IND Non connectable undirected advertising
 * @param       AdvIntervMin    Minimum advertising interval.
 *                  Range: 0x0020 to 0x4000
 *                  Default: 1.28 s
 *                  Time = N * 0.625 msec
 *                  Time Range: 20 ms to 10.24 sec (minimum 100 ms for ADV_SCAN_IND or ADV_NONCONN_IND).
 * @param       AdvIntervMax    Maximum advertising interval.
 *                 Range: 0x0020 to 0x4000
 *                 Default: 2.56 s
 *                 Time = N * 0.625 msec
 *                 Time Range: 20 ms to 10.24 sec  (minimum 100 ms for ADV_SCAN_IND or ADV_NONCONN_IND).
 * @param       OwnAddrType     Type of our address used during advertising
 *                              (@ref PUBLIC_ADDR,@ref STATIC_RANDOM_ADDR).
 * @param       AdvFilterPolicy  Filter policy:
 *                               @arg @ref NO_WHITE_LIST_USE
 *                               @arg @ref WHITE_LIST_FOR_ONLY_SCAN
 *                               @arg @ref WHITE_LIST_FOR_ONLY_CONN
 *                               @arg @ref WHITE_LIST_FOR_ALL
 * @param  LocalNameLen  Length of LocalName array.
 * @param  LocalName  Array containing the Local Name AD data. First byte is the AD type:
 *                       @ref AD_TYPE_SHORTENED_LOCAL_NAME or @ref AD_TYPE_COMPLETE_LOCAL_NAME.
 * @param  ServiceUUIDLen Length of ServiceUUIDList array.
 * @param  ServiceUUIDList  This is the list of the UUIDs AD Types as defined in Volume 3,
 *                Section 11.1.1 of GAP Specification. First byte is the AD Type.
 *                @arg @ref AD_TYPE_16_BIT_SERV_UUID
 *                @arg @ref AD_TYPE_16_BIT_SERV_UUID_CMPLT_LIST
 *                @arg @ref AD_TYPE_128_BIT_SERV_UUID
 *                @arg @ref AD_TYPE_128_BIT_SERV_UUID_CMPLT_LIST
 * @param  SlaveConnIntervMin Slave connection interval minimum value suggested by Peripheral.
 *                If SlaveConnIntervMin and SlaveConnIntervMax are not 0x0000,
 *                Slave Connection Interval Range AD structure will be added in advertising
 *                data.
 *                Connection interval is defined in the following manner:
 *                connIntervalmin = Slave_Conn_Interval_Min x 1.25ms
 *                Slave_Conn_Interval_Min range: 0x0006 to 0x0C80
 *                Value of 0xFFFF indicates no specific minimum.
 * @param  SlaveConnIntervMax Slave connection interval maximum value suggested by Peripheral.
 *                If SlaveConnIntervMin and SlaveConnIntervMax are not 0x0000,
 *                Slave Connection Interval Range AD structure will be added in advertising
 *                data.
 *                ConnIntervalmax = Slave_Conn_Interval_Max x 1.25ms
 *                Slave_Conn_Interval_Max range: 0x0006 to 0x0C80
 *                Slave_ Conn_Interval_Max shall be equal to or greater than the Slave_Conn_Interval_Min.
 *                Value of 0xFFFF indicates no specific maximum.
 *
 * @retval tBleStatus Value indicating success or error code.
 */
tBleStatus aci_gap_set_discoverable(uint8_t AdvType, uint16_t AdvIntervMin, uint16_t AdvIntervMax,
                             uint8_t OwnAddrType, uint8_t AdvFilterPolicy, uint8_t LocalNameLen,
                             const char *LocalName, uint8_t ServiceUUIDLen, uint8_t* ServiceUUIDList,
                             uint16_t SlaveConnIntervMin, uint16_t SlaveConnIntervMax);

#if BLUENRG_MS
///@cond BLUENRG_MS
/**
 * @brief Set the Device in direct connectable mode (as defined in GAP specification Volume 3, Section 9.3.3).
 * @note  If the privacy is enabled, the reconnection address is used for advertising, otherwise the address
 *       of the type specified in OwnAddrType is used. The device will be in directed connectable mode only
 *       for 1.28 seconds. If no connection is established within this duration, the device enters non
 *       discoverable mode and advertising will have to be again enabled explicitly.
 *       The controller generates a @ref EVT_LE_CONN_COMPLETE event with the status set to @ref HCI_DIRECTED_ADV_TIMEOUT
 *       if the connection was not established and 0x00 if the connection was successfully established.
 *
 *       Usage example:
 *       @code
 *
 *       tBleStatus ret;
 *
 *       const uint8_t central_address[] = {0x43,0x27,0x84,0xE1,0x80,0x02};
 *       ret = aci_gap_set_direct_connectable(PUBLIC_ADDR, HIGH_DUTY_CYCLE_DIRECTED_ADV, PUBLIC_ADDR, central_address);
 *       @endcode
 *
 *
 *
 * @param own_addr_type  Type of our address used during advertising (@ref PUBLIC_ADDR,@ref STATIC_RANDOM_ADDR).
 * @param directed_adv_type  Type of directed advertising (@ref HIGH_DUTY_CYCLE_DIRECTED_ADV, @ref LOW_DUTY_CYCLE_DIRECTED_ADV).
 * @param initiator_addr_type Type of peer address (@ref PUBLIC_ADDR,@ref STATIC_RANDOM_ADDR).
 * @param initiator_addr     Initiator's address (Little Endian).
 * @param adv_interv_min     Minimum advertising interval for low duty cycle directed advertsing.
 *                           Range: 0x0020 to 0x4000
 *               Time = N * 0.625 msec
 *               Time Range: 20 ms to 10.24 sec.
 * @param adv_interv_max     Maximum advertising interval for low duty cycle directed advertsing.
 *                           Range: 0x0020 to 0x4000
 *               Time = N * 0.625 msec
 *               Time Range: 20 ms to 10.24 sec.
 * @return Value indicating success or error code.
 */
tBleStatus aci_gap_set_direct_connectable(uint8_t own_addr_type, uint8_t directed_adv_type, uint8_t initiator_addr_type,
                                          const uint8_t *initiator_addr, uint16_t adv_interv_min, uint16_t adv_interv_max);
///@endcond
#else
///@cond BLUENRG
/**
 * @brief Set the Device in direct connectable mode (as defined in GAP specification Volume 3, Section 9.3.3).
 * @note  If the privacy is enabled, the reconnection address is used for advertising, otherwise the address
 *       of the type specified in OwnAddrType is used. The device will be in directed connectable mode only
 *       for 1.28 seconds. If no connection is established within this duration, the device enters non
 *       discoverable mode and advertising will have to be again enabled explicitly.
 *       The controller generates a @ref EVT_LE_CONN_COMPLETE event with the status set to @ref HCI_DIRECTED_ADV_TIMEOUT
 *       if the connection was not established and 0x00 if the connection was successfully established.
 *
 *       Usage example:
 *       @code
 *
 *       tBleStatus ret;
 *
 *       const uint8_t central_address = {0x43,0x27,0x84,0xE1,0x80,0x02};
 *       ret = aci_gap_set_direct_connectable(PUBLIC_ADDR, PUBLIC_ADDR, central_address);
 *       @endcode
 *
 *
 *
 * @param own_addr_type  Type of our address used during advertising (@ref PUBLIC_ADDR,@ref STATIC_RANDOM_ADDR).
 * @param initiator_addr_type Type of peer address (@ref PUBLIC_ADDR,@ref STATIC_RANDOM_ADDR).
 * @param initiator_addr     Initiator's address (Little Endian).
 * @return Value indicating success or error code.
 */
tBleStatus aci_gap_set_direct_connectable(uint8_t own_addr_type, uint8_t initiator_addr_type, const uint8_t *initiator_addr);
///@endcond
#endif

/**
 * @brief Set the IO capabilities of the device.
 * @note This command has to be given only when the device is not in a connected state.
 * @param io_capability One of the allowed codes for IO Capability:
 *       @arg @ref IO_CAP_DISPLAY_ONLY
 *       @arg @ref IO_CAP_DISPLAY_YES_NO
 *       @arg @ref IO_CAP_KEYBOARD_ONLY
 *       @arg @ref IO_CAP_NO_INPUT_NO_OUTPUT
 *       @arg @ref IO_CAP_KEYBOARD_DISPLAY
 * @return Value indicating success or error code.
 */
tBleStatus aci_gap_set_io_capability(uint8_t io_capability);

/**
 * @brief Set the authentication requirements for the device.
 * @note  If the oob_enable is set to 0, oob_data will be ignored.
 *        This command has to be given only when the device is not in a connected state.
 * @param mitm_mode MITM mode:
 *           @arg @ref MITM_PROTECTION_NOT_REQUIRED
 *           @arg @ref MITM_PROTECTION_REQUIRED
 * @param oob_enable If OOB data are present or not:
 *            @arg @ref OOB_AUTH_DATA_ABSENT
 *            @arg @ref OOB_AUTH_DATA_PRESENT
 * @param oob_data   Out-Of-Band data
 * @param min_encryption_key_size Minimum size of the encryption key to be used during the pairing process
 * @param max_encryption_key_size Maximum size of the encryption key to be used during the pairing process
 * @param use_fixed_pin If application wants to use a fixed pin or not:
 *             @arg @ref USE_FIXED_PIN_FOR_PAIRING
 *             @arg @ref DONOT_USE_FIXED_PIN_FOR_PAIRING
 *             If a fixed pin is not used, it has to be provided by the application with
 *             aci_gap_pass_key_response() after @ref EVT_BLUE_GAP_PASS_KEY_REQUEST event.
 * @param fixed_pin If use_fixed_pin is USE_FIXED_PIN_FOR_PAIRING, this is the value of the pin that will
 *           be used during pairing if MIMT protection is enabled. Any value between 0 to 999999 is
 *           accepted.
 * @param bonding_mode One of the bonding modes:
 *              @arg @ref BONDING
 *              @arg @ref NO_BONDING
 * @return Value indicating success or error code.
 */
tBleStatus aci_gap_set_auth_requirement(uint8_t mitm_mode,
                                        uint8_t oob_enable,
                                        uint8_t oob_data[16],
                                        uint8_t min_encryption_key_size,
                                        uint8_t max_encryption_key_size,
                                        uint8_t use_fixed_pin,
                                        uint32_t fixed_pin,
                                        uint8_t bonding_mode);
 /**
  * @brief Set the authorization requirements of the device.
  * @note This command has to be given only when the device is not in a connected state.
  * @param conn_handle Handle of the connection in case BlueNRG is configured as a master (otherwise it can be also 0).
  * @param authorization_enable @arg @ref AUTHORIZATION_NOT_REQUIRED : Authorization not required
  *               @arg @ref AUTHORIZATION_REQUIRED : Authorization required. This enables
  *               the authorization requirement in the device and when a remote device
  *               tries to connect to GATT server, @ref EVT_BLUE_GAP_AUTHORIZATION_REQUEST event
  *               will be sent to the Host.
  *
  * @return Value indicating success or error code.
  */
tBleStatus aci_gap_set_author_requirement(uint16_t conn_handle, uint8_t authorization_enable);

/**
 * @brief Provide the pass key that will be used during pairing.
 * @note This command should be sent by the Host in response to @ref EVT_BLUE_GAP_PASS_KEY_REQUEST event.
 * @param conn_handle Connection handle
 * @param passkey    Pass key that will be used during the pairing process. Must be a number between
 *             0 and 999999.
 * @return Value indicating success or error code.
 */
tBleStatus aci_gap_pass_key_response(uint16_t conn_handle, uint32_t passkey);

/**
 * @brief Authorize a device to access attributes.
 * @note Application should send this command after it has received a @ref EVT_BLUE_GAP_AUTHORIZATION_REQUEST.
 *
 * @param conn_handle Connection handle
 * @param authorize   @arg @ref CONNECTION_AUTHORIZED : Authorize (accept connection)
 *                    @arg @ref CONNECTION_REJECTED : Reject (reject connection)
 * @return Value indicating success or error code.
 */
tBleStatus aci_gap_authorization_response(uint16_t conn_handle, uint8_t authorize);

#if BLUENRG_MS
///@cond BLUENRG_MS
/**
 * @brief Put the device into non-connectable mode.
 * @param adv_type One of the allowed advertising types:
 *                 @arg @ref ADV_SCAN_IND : Scannable undirected advertising
 *                 @arg @ref ADV_NONCONN_IND : Non-connectable undirected advertising
 * @param own_address_type If Privacy is disabled, then the peripheral address can be
 *                      @arg @ref PUBLIC_ADDR.
 *                      @arg @ref STATIC_RANDOM_ADDR.
 *                         If Privacy is enabled, then the peripheral address can be 
 *                         @arg @ref RESOLVABLE_PRIVATE_ADDR
 *                         @arg @ref NON_RESOLVABLE_PRIVATE_ADDR
 * @return Value indicating success or error code.
 */
tBleStatus aci_gap_set_non_connectable(uint8_t adv_type, uint8_t own_address_type);
///@endcond
#else
///@cond BLUENRG
/**
 * @brief Put the device into non-connectable mode.
 * @param adv_type One of the allowed advertising types:
 *                 @arg @ref ADV_SCAN_IND : Scannable undirected advertising
 *                 @arg @ref ADV_NONCONN_IND : Non-connectable undirected advertising
 * @return Value indicating success or error code.
 */
tBleStatus aci_gap_set_non_connectable(uint8_t adv_type);
///@endcond
#endif

/**
 * @brief Put the device into undirected connectable mode.
 * @note  If privacy is enabled in the device, a resolvable private address is generated and used
 *        as the advertiser's address. If not, the address of the type specified in own_addr_type
 *        is used for advertising.
 * @param own_addr_type Type of our address used during advertising:
 *          @cond BLUENRG
 *                   @arg @ref PUBLIC_ADDR.
 *                   @arg @ref STATIC_RANDOM_ADDR.
 *          @endcond
 *          @cond BLUENRG_MS
 *                      If Privacy is disabled:
 *                      @arg @ref PUBLIC_ADDR.
 *                      @arg @ref STATIC_RANDOM_ADDR.
 *                      If Privacy is enabled:
 *                      @arg @ref RESOLVABLE_PRIVATE_ADDR
 *                      @arg @ref NON_RESOLVABLE_PRIVATE_ADDR
 *          @endcond
 * @param adv_filter_policy  Filter policy:
 *                         @arg @ref NO_WHITE_LIST_USE
 *                         @arg @ref WHITE_LIST_FOR_ALL
 * @return Value indicating success or error code.
 */
tBleStatus aci_gap_set_undirected_connectable(uint8_t own_addr_type, uint8_t adv_filter_policy);

/**
 * @brief Send a slave security request to the master.
 * @note This command has to be issued to notify the master of the security requirements of the slave.
 *      The master may encrypt the link, initiate the pairing procedure, or reject the request.
 * @param conn_handle Connection handle
 * @param bonding     One of the bonding modes:
 *              @arg @ref BONDING
 *              @arg @ref NO_BONDING
 * @param mitm_protection  If MITM protection is required or not:
 *                @arg @ref MITM_PROTECTION_NOT_REQUIRED
 *                @arg @ref MITM_PROTECTION_REQUIRED
 * @return Value indicating success or error code.
 */
tBleStatus aci_gap_slave_security_request(uint16_t conn_handle, uint8_t bonding, uint8_t mitm_protection);

/**
 * @brief Update advertising data.
 * @note This command can be used to update the advertising data for a particular AD type.
 *       If the AD type specified does not exist, then it is added to the advertising data.
 *       If the overall advertising data length is more than 31 octets after the update, then
 *       the command is rejected and the old data is retained.
 * @param AdvLen Length of AdvData array
 * @param AdvData Advertisement Data,  formatted as specified in Bluetooth specification
 *        (Volume 3, Part C, 11), including data length. It can contain more than one AD type.
 *        Example
 * @code
 *  tBleStatus ret;
 *  const char local_name[] = {AD_TYPE_COMPLETE_LOCAL_NAME,'B','l','u','e','N','R','G'};
 *  const uint8_t serviceUUIDList[] = {AD_TYPE_16_BIT_SERV_UUID,0x34,0x12};
 *  const uint8_t manuf_data[] = {4, AD_TYPE_MANUFACTURER_SPECIFIC_DATA, 0x05, 0x02, 0x01};
 *
 *  ret = aci_gap_set_discoverable(ADV_IND, 0, 0, STATIC_RANDOM_ADDR, NO_WHITE_LIST_USE,
 *                                 8, local_name, 3, serviceUUIDList, 0, 0);
 *  ret = aci_gap_update_adv_data(5, manuf_data);
 * @endcode
 *
 * @return Value indicating success or error code.
 */
tBleStatus aci_gap_update_adv_data(uint8_t AdvLen, const uint8_t *AdvData);

/**
 * @brief Delete an AD Type
 * @note This command can be used to delete the specified AD type from the advertisement data if
 *      present.
 * @param ad_type One of the allowed AD types (see @ref AD_Types)
 * @return Value indicating success or error code.
 */
tBleStatus aci_gap_delete_ad_type(uint8_t ad_type);

/**
 * @brief Get the current security settings
 * @note This command can be used to get the current security settings of the device.
 * @param mitm_protection   @arg 0: Not required
 *                          @arg 1: Required
 * @param bonding       @arg 0: No bonding mode
 *                      @arg 1: Bonding mode
 * @param oob_data      @arg 0: Data absent
 *                      @arg 1: Data present
 * @param passkey_required  @arg 0: Not required
 *                          @arg 1: Fixed pin is present which is being used
 *                          @arg 2: Passkey required for pairing. An event will be generated
 *                          when required.
 * @return Value indicating success or error code.
 */
tBleStatus aci_gap_get_security_level(uint8_t* mitm_protection, uint8_t* bonding,
                                      uint8_t* oob_data, uint8_t* passkey_required);

/**
 * @brief Add addresses of bonded devices into the controller's whitelist.
 * @note  The command will return an error if there are no devices in the database or if it was unable
 *       to add the device into the whitelist.
 * @return Value indicating success or error code.
 */
tBleStatus aci_gap_configure_whitelist(void);

/**
 * @brief Terminate a connection.
 * @note  A @ref EVT_DISCONN_COMPLETE event will be generated when the link is disconnected.
 * @param conn_handle Connection handle
 * @param reason  Reason for requesting disconnection. The error code can be any of ones as specified
 *           for the disconnected command in the HCI specification (See @ref HCI_Error_codes).
 * @return Value indicating success or error code.
 */
tBleStatus aci_gap_terminate(uint16_t conn_handle, uint8_t reason);

/**
 * @brief Clear the security database.
 * @note  All the devices in the security database will be removed.
 * @return Value indicating success or error code.
 */
tBleStatus aci_gap_clear_security_database(void);

#if BLUENRG_MS
///@cond BLUENRG_MS
/**
 * @brief Allows the security manager to complete the pairing procedure and re-bond with the master.
 * @note This command can be issued by the application if a @ref EVT_BLUE_GAP_BOND_LOST event is generated.
 * @param conn_handle 
 * @return Value indicating success or error code.
 */
tBleStatus aci_gap_allow_rebond(uint16_t conn_handle);
///@endcond
#else
///@cond BLUENRG
/**
 * @brief Allows the security manager to complete the pairing procedure and re-bond with the master.
 * @note This command can be issued by the application if a @ref EVT_BLUE_GAP_BOND_LOST event is generated.
 * @return Value indicating success or error code.
 */
tBleStatus aci_gap_allow_rebond(void);
///@endcond
#endif

/**
 * @brief Start the limited discovery procedure.
 * @note  The controller is commanded to start active scanning. When this procedure is started,
 *        only the devices in limited discoverable mode are returned to the upper layers.
 *        The procedure is terminated when either the upper layers issue a command to terminate the
 *        procedure by issuing the command aci_gap_terminate_gap_procedure() with the procedure code
 *        set to @ref GAP_LIMITED_DISCOVERY_PROC or a timeout happens. When the procedure is terminated
 *        due to any of the above  reasons, @ref EVT_BLUE_GAP_PROCEDURE_COMPLETE event is returned with
 *        the procedure code set to @ref GAP_LIMITED_DISCOVERY_PROC.
 *        The device found when the procedure is ongoing is returned to the upper layers through the
 *        event @cond BLUENRG_MS @ref EVT_LE_ADVERTISING_REPORT.@endcond @cond BLUENRG @ref EVT_BLUE_GAP_DEVICE_FOUND.@endcond
 * @param scanInterval Time interval from when the Controller started its last LE scan until it begins
 *              the subsequent LE scan. The scan interval should be a number in the range
 *              0x0004 to 0x4000. This corresponds to a time range 2.5 msec to 10240 msec.
 *              For a number N, Time = N x 0.625 msec.
 * @param scanWindow Amount of time for the duration of the LE scan. Scan_Window shall be less than
 *            or equal to Scan_Interval. The scan window should be a number in the range
 *            0x0004 to 0x4000. This corresponds to a time range 2.5 msec to 10240 msec.
 *            For a number N, Time = N x 0.625 msec.
 * @param own_address_type Type of our address used during advertising (@ref PUBLIC_ADDR, @ref STATIC_RANDOM_ADDR).
 * @param filterDuplicates Duplicate filtering enabled or not.
 *                @arg 0x00: Do not filter the duplicates
 *                @arg 0x01: Filter duplicates
 *
 * @return Value indicating success or error code.
 */
tBleStatus aci_gap_start_limited_discovery_proc(uint16_t scanInterval, uint16_t scanWindow,
            uint8_t own_address_type, uint8_t filterDuplicates);

/**
 * @brief Start the general discovery procedure.
 * @note  The controller is commanded to start active scanning. The procedure is terminated when
 *       either the upper layers issue a command to terminate the procedure by issuing the command
 *       aci_gap_terminate_gap_procedure() with the procedure code set to GAP_GENERAL_DISCOVERY_PROC
 *       or a timeout happens. When the procedure is terminated due to any of the above reasons,
 *       @ref EVT_BLUE_GAP_PROCEDURE_COMPLETE event is returned with the procedure code set to
 *       @ref GAP_GENERAL_DISCOVERY_PROC. The device found when the procedure is ongoing is returned to
 *      the upper layers through the event @cond BLUENRG_MS @ref EVT_LE_ADVERTISING_REPORT.@endcond @cond BLUENRG @ref EVT_BLUE_GAP_DEVICE_FOUND.@endcond
 * @param scanInterval Time interval from when the Controller started its last LE scan until it begins
 *              the subsequent LE scan. The scan interval should be a number in the range
 *              0x0004 to 0x4000. This corresponds to a time range 2.5 msec to 10240 msec.
 *              For a number N, Time = N x 0.625 msec.
 * @param scanWindow Amount of time for the duration of the LE scan. Scan_Window shall be less than
 *            or equal to Scan_Interval. The scan window should be a number in the range
 *            0x0004 to 0x4000. This corresponds to a time range 2.5 msec to 10240 msec.
 *            For a number N, Time = N x 0.625 msec.
 * @param own_address_type Type of our address used during advertising (@ref PUBLIC_ADDR, @ref STATIC_RANDOM_ADDR).
 * @param filterDuplicates Duplicate filtering enabled or not.
 *                @arg 0x00: Do not filter the duplicates
 *                @arg 0x01: Filter duplicates
 *
 * @return Value indicating success or error code.
 */
tBleStatus aci_gap_start_general_discovery_proc(uint16_t scanInterval, uint16_t scanWindow,
            uint8_t own_address_type, uint8_t filterDuplicates);

/**
 * @brief Start the name discovery procedure.
 * @note  A LE_Create_Connection call will be made to the controller by GAP with the initiator filter

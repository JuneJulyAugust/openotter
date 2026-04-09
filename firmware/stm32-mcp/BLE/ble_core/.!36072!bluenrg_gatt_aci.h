/******************** (C) COPYRIGHT 2014 STMicroelectronics ********************
* File Name          : bluenrg_gatt_aci.h
* Author             : AMS - AAS
* Version            : V1.0.0
* Date               : 26-Jun-2014
* Description        : Header file with GATT commands for BlueNRG FW6.3.
********************************************************************************
* This software is licensed under terms that can be found in the LICENSE file
* in the root directory of this software component.
* If no LICENSE file comes with this software, it is provided AS-IS.
*******************************************************************************/

#ifndef __BLUENRG_GATT_ACI_H__
#define __BLUENRG_GATT_ACI_H__

#include "bluenrg_gatt_server.h"

/**
 *@addtogroup GATT GATT
 *@brief GATT layer.
 *@{
 */

/**
 *@defgroup GATT_Functions GATT functions
 *@brief API for GATT layer.
 *@{
 */

/**
  * @brief  Initialize the GATT layer for server and client roles.
  * @note   It adds also the GATT service with Service Changed Characteristic.
 *           Until this command is issued the GATT channel will not process any commands
  *          even if the connection is opened. This command has to be given
  *          before using any of the GAP features.
  * @return Value indicating success or error code.
  */
tBleStatus aci_gatt_init(void);

/**
 * @brief Add a service to the GATT Server. When a service is created in the server, the Host needs
 *        to reserve the handle ranges for this service using max_attr_records parameter. This
 *        parameter specifies the maximum number of attribute records that can be added to this
 *        service (including the service attribute, include attribute, characteristic attribute,
 *        characteristic value attribute and characteristic descriptor attribute). Handle of the
 *        created service is returned.
 * @note  Service declaration is taken from the service pool. The attributes for characteristics and descriptors
 *            are allocated from the attribute pool.
 * @param service_uuid_type Type of service UUID (16-bit or 128-bit). See @ref UUID_Types "UUID Types".
 * @param[in] service_uuid 16-bit or 128-bit UUID based on the UUID Type field
 * @param service_type Primary or secondary service. See @ref Service_type "Service Type".
 * @param max_attr_records Maximum number of attribute records that can be added to this service
 *                         (including the service declaration itself)
 * @param[out] serviceHandle Handle of the Service. When this service is added to the service,
 * 							 a handle is allocated by the server to this service. Server also
 * 							 allocates a range of handles for this service from serviceHandle to
 * 							 <serviceHandle + max_attr_records>.
 * @return Value indicating success or error code.
 */
tBleStatus aci_gatt_add_serv(uint8_t service_uuid_type,
			     const uint8_t* service_uuid,
			     uint8_t service_type,
			     uint8_t max_attr_records,
			     uint16_t *serviceHandle);

/**
 * @brief Include a service given by included_start_handle and included_end_handle to another service
 * 		  given by service_handle. Attribute server creates an INCLUDE definition attribute and return
 * 		  the handle of this attribute in included_handle.
 * @param service_handle Handle of the service to which another service has to be included
 * @param included_start_handle Start Handle of the service which has to be included in service
 * @param included_end_handle End Handle of the service which has to be included in service
 * @param included_uuid_type Type of UUID for included service (16-bit or 128-bit). See @ref Well-Known_UUIDs "Well-Known UUIDs".
 * @param[in] included_uuid 16-bit or 128-bit UUID.
 * @param[out] included_handle Handle of the include declaration.
 * @return Value indicating success or error code.
 */
tBleStatus aci_gatt_include_service(uint16_t service_handle, uint16_t included_start_handle,
				    uint16_t included_end_handle, uint8_t included_uuid_type,
				    const uint8_t* included_uuid, uint16_t *included_handle);

/**
 * @brief Add a characteristic to a service.
 * @param serviceHandle Handle of the service to which the characteristic has to be added.
 * @param charUuidType Type of characteristic UUID (16-bit or 128-bit). See @ref UUID_Types "UUID Types".
 *         @arg @ref UUID_TYPE_16
 *         @arg @ref UUID_TYPE_128
 * @param charUuid 16-bit or 128-bit UUID.
 * @param charValueLen Maximum length of the characteristic value.
 * @param charProperties Bitwise OR values of Characteristic Properties (defined in Volume 3,
 *        Section 3.3.3.1 of Bluetooth Specification 4.0). See @ref Char_properties "Characteristic properties".
 * @param secPermissions Security permissions for the added characteristic. See @ref Security_permissions "Security permissions".
 * 			@arg ATTR_PERMISSION_NONE
 * 			@arg ATTR_PERMISSION_AUTHEN_READ
 * 			@arg ATTR_PERMISSION_AUTHOR_READ
 * 			@arg ATTR_PERMISSION_ENCRY_READ
 * 			@arg ATTR_PERMISSION_AUTHEN_WRITE
 * 			@arg ATTR_PERMISSION_AUTHOR_WRITE
 * 			@arg ATTR_PERMISSION_ENCRY_WRITE
 * @param gattEvtMask Bit mask that enables events that will be sent to the application by the GATT server
 * 					  on certain ATT requests. See @ref Gatt_Event_Mask "Gatt Event Mask".
 * 		   @arg GATT_DONT_NOTIFY_EVENTS
 * 		   @arg GATT_NOTIFY_ATTRIBUTE_WRITE
 * 		   @arg GATT_NOTIFY_WRITE_REQ_AND_WAIT_FOR_APPL_RESP
 * 		   @arg GATT_NOTIFY_READ_REQ_AND_WAIT_FOR_APPL_RESP
 * @param encryKeySize The minimum encryption key size requirement for this attribute. Valid Range: 7 to 16.
 * @param isVariable If the attribute has a variable length value field (1) or not (0).
 * @param charHandle Handle of the Characteristic that has been added. It is the handle of the characteristic declaration.
 * 		  The attribute that holds the characteristic value is allocated at the next handle, followed by the Client
 * 		  Characteristic Configuration descriptor if the characteristic has @ref CHAR_PROP_NOTIFY or @ref CHAR_PROP_INDICATE
 * 		  properties.
 * @return Value indicating success or error code.
 */
tBleStatus aci_gatt_add_char(uint16_t serviceHandle,
			     uint8_t charUuidType,
			     const uint8_t* charUuid,
#if (BLUENRG1 == 1)				  
			     uint16_t charValueLen, 
#else
			     uint8_t charValueLen,
#endif				 
			     uint8_t charProperties,
			     uint8_t secPermissions,
			     uint8_t gattEvtMask,
			     uint8_t encryKeySize,
			     uint8_t isVariable,
			     uint16_t* charHandle);

/**
 * Add a characteristic descriptor to a service.
 * @param serviceHandle Handle of the service to which the characteristic belongs
 * @param charHandle Handle of the characteristic to which description has to be added.
 * @param descUuidType 16-bit or 128-bit UUID. See @ref UUID_Types "UUID Types".
 *         @arg @ref UUID_TYPE_16
 *         @arg @ref UUID_TYPE_128
 * @param[in] uuid UUID of the Characteristic descriptor. It can be one of the UUID assigned by Bluetooth SIG
 * 		(Well_known_UUIDs) or a user-defined one.
 * @param descValueMaxLen The maximum length of the descriptor value
 * @param descValueLen Current Length of the characteristic descriptor value
 * @param[in] descValue Value of the characteristic description
 * @param secPermissions Security permissions for the added descriptor. See @ref Security_permissions "Security permissions".
 * 			@arg ATTR_PERMISSION_NONE
 * 			@arg ATTR_PERMISSION_AUTHEN_READ
 * 			@arg ATTR_PERMISSION_AUTHOR_READ
 * 			@arg ATTR_PERMISSION_ENCRY_READ
 * 			@arg ATTR_PERMISSION_AUTHEN_WRITE
 * 			@arg ATTR_PERMISSION_AUTHOR_WRITE
 * 			@arg ATTR_PERMISSION_ENCRY_WRITE
 * @param accPermissions Access permissions for the added descriptor. See @ref Access_permissions "Access permissions".
 * 			@arg ATTR_NO_ACCESS
 * 			@arg ATTR_ACCESS_READ_ONLY
 * 			@arg ATTR_ACCESS_WRITE_REQ_ONLY
 * 			@arg ATTR_ACCESS_READ_WRITE
 * 			@arg ATTR_ACCESS_WRITE_WITHOUT_RESPONSE
 * 			@arg ATTR_ACCESS_SIGNED_WRITE_ALLOWED
 * @param gattEvtMask Bit mask that enables events that will be sent to the application by the GATT server
 * 					  on certain ATT requests. See @ref Gatt_Event_Mask "Gatt Event Mask".
 * @param encryKeySize The minimum encryption key size requirement for this attribute. Valid Range: 7 to 16.
 * @param isVariable If the attribute has a variable length value field (1) or not (0).
 * @param[out] descHandle Handle of the Characteristic Descriptor.
 * @return Value indicating success or error code.
 */
tBleStatus aci_gatt_add_char_desc(uint16_t serviceHandle,
                                  uint16_t charHandle,
                                  uint8_t descUuidType,
                                  const uint8_t* uuid, 
                                  uint8_t descValueMaxLen,
                                  uint8_t descValueLen,
                                  const void* descValue, 
                                  uint8_t secPermissions,
                                  uint8_t accPermissions,
                                  uint8_t gattEvtMask,
                                  uint8_t encryKeySize,
                                  uint8_t isVariable,
                                  uint16_t* descHandle);

/**
 * @brief Update a characteristic value in a service.
 * @note If notifications (or indications) are enabled on that characteristic, a notification (or indication)
 *   	 will be sent to the client after sending this command to the BlueNRG. The command is queued into the
 *   	 BlueNRG command queue. If the buffer is full, because previous commands could not be still processed,
 *   	 the function will return @ref BLE_STATUS_INSUFFICIENT_RESOURCES. This will happen if notifications (or
 *   	 indications) are enabled and the application calls aci_gatt_update_char_value() at an higher rate
 *   	 than what is allowed by the link. Throughput on BLE link depends on connection interval and
 *   	 connection length parameters (decided by the master, see aci_l2cap_connection_parameter_update_request()
 *   	 for more info on how to suggest new connection parameters from a slave). If the application does not
 *   	 want to lose notifications because BlueNRG buffer becomes full, it has to retry again till the function
 *   	 returns @ref BLE_STATUS_SUCCESS or any other error code.\n
 *   	 Example:\n
 *   	 Here if BlueNRG buffer become full because BlueNRG was not able to send packets for a while, some
 *   	 notifications will be lost.
 *   	 @code
 *   	 tBleStatus Free_Fall_Notify(void)
 *		 {
 *		 	uint8_t val;
 * 			tBleStatus ret;
 *
 *			val = 0x01;
 *			ret = aci_gatt_update_char_value(accServHandle, freeFallCharHandle, 0, 1, &val);
 *
 *			if (ret != BLE_STATUS_SUCCESS){
 *			  PRINTF("Error while updating ACC characteristic.\n") ;
 *			  return BLE_STATUS_ERROR ;
 *			}
 *		    return BLE_STATUS_SUCCESS;
 *		 }
 *		 @endcode
 *		 Here if BlueNRG buffer become full, the application try again to send the notification.
 *		 @code
 *       struct timer t;
 *       Timer_Set(&t, CLOCK_SECOND*10);
 *       while(aci_gatt_update_char_value(chatServHandle,TXCharHandle,0,len,array_val)==BLE_STATUS_INSUFFICIENT_RESOURCES){
 *         // Radio is busy (buffer full).
 *         if(Timer_Expired(&t))
 *           break;
 *       }
 *       @endcode
 *
 * @param servHandle Handle of the service to which characteristic belongs
 * @param charHandle Handle of the characteristic
 * @param charValOffset The offset from which the attribute value has to be updated. If this is set to 0,
 * 						and the attribute value is of variable length, then the length of the attribute will
 * 						be set to the charValueLen. If the charValOffset is set to a value greater than 0,
 * 						then the length of the attribute will be set to the maximum length as specified for
 * 						the attribute while adding the characteristic.
 * @param charValueLen Length of the characteristic value in octets
 * @param[in] charValue Characteristic value
 * @return Value indicating success or error code.
 */
tBleStatus aci_gatt_update_char_value(uint16_t servHandle, 
				      uint16_t charHandle,
				      uint8_t charValOffset,
				      uint8_t charValueLen,   
                                      const void *charValue);
/**
 * @brief Delete the specified characteristic from the service.
 * @param servHandle Handle of the service to which characteristic belongs
 * @param charHandle Handle of the characteristic to be deleted
 * @return Value indicating success or error code.
 */
tBleStatus aci_gatt_del_char(uint16_t servHandle, uint16_t charHandle);

/**
 * @brief Delete the specified service from the GATT server database.
 * @param servHandle Handle of the service to be deleted
 * @return Value indicating success or error code.
 */
tBleStatus aci_gatt_del_service(uint16_t servHandle);

/**
 * @brief Delete the Include definition from the service.
 * @param servHandle Handle of the service to which Include definition belongs
 * @param includeServHandle Handle of the Included definition to be deleted
 * @return Value indicating success or error code.
 */
tBleStatus aci_gatt_del_include_service(uint16_t servHandle, uint16_t includeServHandle);

/**
 * @brief Perform an ATT MTU exchange procedure.
 * @note  When the ATT MTU exchange procedure is completed, a @ref EVT_BLUE_ATT_EXCHANGE_MTU_RESP
 * 		  event is generated. A @ref EVT_BLUE_GATT_PROCEDURE_COMPLETE event is also generated
 * 		  to indicate the end of the procedure.
 * @param conn_handle Connection handle for which the command is given.
 * @return Value indicating success or error code.
 */
tBleStatus aci_gatt_exchange_configuration(uint16_t conn_handle);

/**
 * @brief Send a @a Find @a Information @a Request.
 * @note This command is used to obtain the mapping of attribute handles with their associated
 * 		 types. The responses of the procedure are given through the
 * 		 @ref EVT_BLUE_ATT_FIND_INFORMATION_RESP event. The end of the procedure is indicated by
 * 		 a @ref EVT_BLUE_GATT_PROCEDURE_COMPLETE event.
 * @param conn_handle Connection handle for which the command is given
 * @param start_handle Starting handle of the range of attributes to be discovered on the server
 * @param end_handle Ending handle of the range of attributes to be discovered on the server
 * @return Value indicating success or error code.
 */
tBleStatus aci_att_find_information_req(uint16_t conn_handle, uint16_t start_handle, uint16_t end_handle);

/**
 * @brief Send a @a Find @a By @a Type @a Value @a Request
 * @note The Find By Type Value Request is used to obtain the handles of attributes that
 * 		 have a given 16-bit UUID attribute type and a given attribute value.
 * 		 The responses of the procedure are given through the @ref EVT_BLUE_ATT_FIND_BY_TYPE_VAL_RESP event.
 * 		 The end of the procedure is indicated by a @ref EVT_BLUE_GATT_PROCEDURE_COMPLETE event.
 * @param conn_handle Connection handle for which the command is given.
 * @param start_handle 	First requested handle number
 * @param end_handle 	Last requested handle number
 * @param uuid			2 octet UUID to find (little-endian)
 * @param attr_val_len  Length of attribute value (maximum value is ATT_MTU - 7).
 * @param attr_val		Attribute value to find
 * @return Value indicating success or error code.
 */
tBleStatus aci_att_find_by_type_value_req(uint16_t conn_handle, uint16_t start_handle, uint16_t end_handle,
                                          uint8_t* uuid, uint8_t attr_val_len, uint8_t* attr_val);

/**
 * @brief Send a @a Read @a By @a Type @a Request
 * @note  The Read By Type Request is used to obtain the values of attributes where the attribute type
 * 		  is known but the handle is not known.
 * 		  The responses of the procedure are given through the @ref EVT_BLUE_ATT_READ_BY_TYPE_RESP event.
 * 		  The end of the procedure is indicated by a @ref EVT_BLUE_GATT_PROCEDURE_COMPLETE event.
 * @param conn_handle Connection handle for which the command is given.
 * @param start_handle First requested handle number
 * @param end_handle Last requested handle number
 * @param uuid_type @arg @ref UUID_TYPE_16
 *         			@arg @ref UUID_TYPE_128
 * @param uuid 2 or 16 octet UUID
 * @return Value indicating success or error code.
 */
tBleStatus aci_att_read_by_type_req(uint16_t conn_handle, uint16_t start_handle, uint16_t end_handle,
                                    uint8_t  uuid_type, uint8_t* uuid);

/**
 * @brief Send a @a Read @a By @a Group @a Type @a Request
 * @note The Read By Group Type Request is used to obtain the values of grouping attributes where the attribute
 * 		 type is known but the handle is not known. Grouping attributes are defined at GATT layer. The grouping

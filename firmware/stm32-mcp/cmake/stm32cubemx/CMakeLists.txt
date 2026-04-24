cmake_minimum_required(VERSION 3.22)
# Enable CMake support for ASM and C languages
enable_language(C ASM)
# STM32CubeMX generated symbols (macros)
set(MX_Defines_Syms
	USE_HAL_DRIVER
	STM32L475xx
	BLUENRG_MS=1
    $<$<CONFIG:Debug>:DEBUG>
)

# STM32CubeMX generated include paths
set(MX_Include_Dirs
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Core/Inc
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Inc
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Inc/Legacy
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/CMSIS/Device/ST/STM32L4xx/Include
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/CMSIS/Include
    # BLE middleware includes
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/ble_core
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/ble_services
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/hw
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/tl
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/utilities
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/debug
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE
    # VL53L1CB bare driver includes
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/VL53L1CB/core/inc
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/VL53L1CB/platform/inc
)

# STM32CubeMX generated application sources
set(MX_Application_Src
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Core/Src/main.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Core/Src/ble_app.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Core/Src/rev_safety.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Core/Src/rev_safety_tof.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Core/Src/tof_l1.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Core/Src/tof_l1_roi.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Core/Src/ble_tof.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Core/Src/stm32l4xx_it.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Core/Src/stm32l4xx_hal_msp.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Core/Src/sysmem.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Core/Src/syscalls.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../startup_stm32l475xx.s
)

# STM32 HAL/LL Drivers
set(STM32_Drivers_Src
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Core/Src/system_stm32l4xx.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_dfsdm.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_rcc.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_rcc_ex.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_flash.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_flash_ex.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_flash_ramfunc.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_gpio.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_i2c.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_i2c_ex.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_dma.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_dma_ex.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_pwr.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_pwr_ex.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_cortex.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_exti.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_qspi.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_spi.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_spi_ex.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_tim.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_tim_ex.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_uart.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_uart_ex.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_pcd.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_pcd_ex.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_ll_usb.c
    # Additional drivers needed for BLE middleware
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_rtc.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_hal_rtc_ex.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/STM32L4xx_HAL_Driver/Src/stm32l4xx_ll_rcc.c
)

# BLE Middleware sources (BlueNRG-MS stack)
set(BLE_Middleware_Src
    # BLE Core (HCI, GAP, GATT, HAL ACI)
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/ble_core/bluenrg_gap_aci.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/ble_core/bluenrg_gatt_aci.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/ble_core/bluenrg_hal_aci.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/ble_core/bluenrg_l2cap_aci.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/ble_core/hci_le.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/ble_core/osal.c
    # Transport Layer (SPI protocol)
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/tl/tl_ble_hci.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/tl/tl_ble_io.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/tl/tl_ble_reassembly.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/tl/tl_ble_spi.c
    # Hardware Abstraction (SPI driver, timer server, LPM)
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/hw/hw_spi.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/hw/hw_timerserver.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/hw/hw_lpm.c
    # Services (service controller, LED Button service template)
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/ble_services/svc_ctl.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/ble_services/lbs_stm.c
    # Utilities (scheduler, memory, queue, list, LPM)
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/utilities/scheduler.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/utilities/memory_manager.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/utilities/queue.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/utilities/list.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../BLE/utilities/lpm.c
)


# VL53L1CB bare driver sources (globbed so new files stay picked up automatically)
file(GLOB VL53L1CB_Src CONFIGURE_DEPENDS
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/VL53L1CB/core/src/*.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../../Drivers/VL53L1CB/platform/src/*.c
)


# Link directories setup
set(MX_LINK_DIRS

)
# Project static libraries
set(MX_LINK_LIBS
    STM32_Drivers
    BLE_Middleware
    VL53L1CB_Driver
    ${TOOLCHAIN_LINK_LIBRARIES}

)
# Interface library for includes and symbols
add_library(stm32cubemx INTERFACE)
target_include_directories(stm32cubemx INTERFACE ${MX_Include_Dirs})
target_compile_definitions(stm32cubemx INTERFACE ${MX_Defines_Syms})

# Create STM32_Drivers static library
add_library(STM32_Drivers OBJECT)
target_sources(STM32_Drivers PRIVATE ${STM32_Drivers_Src})
target_link_libraries(STM32_Drivers PUBLIC stm32cubemx)

# Create BLE_Middleware static library
add_library(BLE_Middleware OBJECT)
target_sources(BLE_Middleware PRIVATE ${BLE_Middleware_Src})
target_link_libraries(BLE_Middleware PUBLIC stm32cubemx)

# Create VL53L1CB_Driver static library (linker --gc-sections strips unused modes)
add_library(VL53L1CB_Driver OBJECT)
target_sources(VL53L1CB_Driver PRIVATE ${VL53L1CB_Src})
target_link_libraries(VL53L1CB_Driver PUBLIC stm32cubemx)


# Add STM32CubeMX generated application sources to the project
target_sources(${CMAKE_PROJECT_NAME} PRIVATE ${MX_Application_Src})

# Link directories setup
target_link_directories(${CMAKE_PROJECT_NAME} PRIVATE ${MX_LINK_DIRS})

# Add libraries to the project
target_link_libraries(${CMAKE_PROJECT_NAME} ${MX_LINK_LIBS})

# Add the map file to the list of files to be removed with 'clean' target
set_target_properties(${CMAKE_PROJECT_NAME} PROPERTIES ADDITIONAL_CLEAN_FILES ${CMAKE_PROJECT_NAME}.map)

# Validate that STM32CubeMX code is compatible with C standard
if((CMAKE_C_STANDARD EQUAL 90) OR (CMAKE_C_STANDARD EQUAL 99))
    message(ERROR "Generated code requires C11 or higher")
endif()

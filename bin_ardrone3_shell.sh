#!/bin/sh

PRODUCT="BebopDrone"

# File containing a 4MB filesystem with the FVT6 flash report
# Only used once, can be stored in tmp memory
ARDRONE3_USBDISKIMG_PATH="/tmp/imgdisk.bin"
ARDRONE3_USBDISKIMG_MOUNT_PATH="/tmp/imgdisk"

# Mount path of eMMC
ARDRONE3_MOUNT_PATH="/data/ftp/internal_000"

# Paths inside eMMC
ARDRONE3_DEBUG_PATH="${ARDRONE3_MOUNT_PATH}/Debug"

ARDRONE3_DEBUG_CUR_DIR="${ARDRONE3_DEBUG_PATH}/current"

ARDRONE3_DEBUG_ARCH_DIR="${ARDRONE3_DEBUG_PATH}/archive"

ARDRONE3_STORAGE_PATH="${ARDRONE3_MOUNT_PATH}/Bebop_Drone"

ARDRONE3_FLIGHT_PLANS_PATH="${ARDRONE3_MOUNT_PATH}/flightplans"

ARDRONE3_BLACKBOX_PATH="${ARDRONE3_DEBUG_CUR_DIR}/blackbox"

ARDRONE3_CKCM_PATH="${ARDRONE3_DEBUG_CUR_DIR}/ckcm"

ARDRONE3_CORES_PATH="${ARDRONE3_DEBUG_CUR_DIR}/cores"

ARDRONE3_SCRIPTS_PATH="${ARDRONE3_MOUNT_PATH}/scripts"

ARDRONE3_LOGS_PATH="${ARDRONE3_MOUNT_PATH}/log"

# Path of file containing serial number
FACTORY_SERIAL_FILE="/factory/serial.txt"
# path of file containing MAC address
FACTORY_MAC_ADDR_FILE="/factory/mac_address.txt"
# Path of file containing factory country setting
FACTORY_COUNTRY_SETTING_FILE="/factory/country_setting.txt"

# Dragon configuration
DRAGON_CONF="/data/dragon.conf"
DEFAULT_DRAGON_CONF="/etc/default-dragon.conf"
# System configuration
DEFAULT_SYSTEM_CONF="/etc/default-system.conf"
SYSTEM_CONF="/data/system.conf"

##### COOKIE FILES
COOKIE_BOOT_DIR=/tmp/run/init

# BOOT FLAGS
NET_WIFI_BCM_STARTED="${COOKIE_BOOT_DIR}/network_started"

##### NETWORK
NET_STATE_DIR="/tmp/run/network_state"
NET_STATE_WIFI_BCM="${NET_STATE_DIR}/wifi_bcm_state"
NET_STATE_USB_ETH="${NET_STATE_DIR}/usb_eth_state"
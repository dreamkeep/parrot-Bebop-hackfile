#!/bin/sh

source /bin/ardrone3_shell.sh

FVT6FILE=/data/fvt6.txt
FVT6TMPFILE=/tmp/fvt6.new.txt
FVT6TRIGGER=/fvt6.trigger

FVT6_LOG()
{
  echo $1 >> ${FVT6TMPFILE}
  echo $1 | logger -s -t "FVT6" -p user.info
}

FVT6_EXIT()
{
  echo [FVT6] $1  | logger -s -t "FVT6" -p user.info
  exit;
}

checkUSB()
{
  if [ "$(lsusb | grep $1)" != "" ]; then echo -e "OK"; else echo -e "KO"; fi
}

checkWITF()
{
  if [ "$(bcmwl status 2>/dev/null | grep SSID)" != "" ]; then echo -e "OK"; else echo -e "KO"; fi
}

checkI2C()
{
  if [ "$(I2C_DEVICE=/dev/i2c-$2 i2c_cmd | grep 'present' | grep -o $3)" == "$3" ];
  then
    echo -e "OK";
  else
    echo -e "KO";
  fi
}


checkFile()
{
  if [ -e $1 ]; then echo -e "OK"; else echo -e "KO"; fi
}

modprobe loop
create_imgdisk.sh ${ARDRONE3_USBDISKIMG_PATH} ${ARDRONE3_USBDISKIMG_MOUNT_PATH} 4 "BebopDrone" | logger -s -t "FVT6" -p user.info

# Check that the factory partition was mounted and is in the expected state (readonly)
if [ "$(mount | grep factory)" != "ubi0:factory on /factory type ubifs (ro,relatime)" ]
then
  echo "Unexpected factory partition state" | logger -s -t "FVT6" -p user.error
fi

# Only generate the log once
# Stored in /etc so that:
#  it is not regenerated during customer updates
#  it is regenerated after each factory updates
if [ ! -f ${FVT6TRIGGER} ]; then FVT6_EXIT "FVT6 log already generated"; fi

# If the script was previously interrupted, clean up what's left
rm ${FVT6TMPFILE} -f

# Set /etc and /factory to RW
for partoche in / /factory; do
mount ${partoche} -o remount,rw
if [ $? != 0 ]; then FVT6_EXIT "Could not get write access to ${partoche}"; fi
done

# Start testing & logging
FVT6_LOG "#"
FVT6_LOG "# Bebop Drone FVT6 firmware status"
FVT6_LOG "#"
FVT6_LOG ""

FVT6_LOG "[General Information]"
FVT6_LOG "ProductName=BebopDrone"
FVT6_LOG "DroneName=$(cat /etc/default-dragon.conf |  grep \"product_name\" | cut -d ':' -f 2 | sed 's@[\\\",]@@g')"
FVT6_LOG "SerialNumber=$(cat /factory/serial.txt)"
FVT6_LOG "FWVersion=$(cat /version.txt)"
FVT6_LOG "HWVersion=$(cat /sys/kernel/hsis/hwrev)"
FVT6_LOG "MACAddress=$(cat /factory/mac_address.txt)"
FVT6_LOG ""

FVT6_LOG "[Sensors]"
FVT6_LOG "MT9F002=$(checkI2C "" 0 0x10)"
# The MT9V117 camera does not run at this point
#FVT6_LOG "MT9V117=$(checkI2C "" 0 0x5d)"
FVT6_LOG "WIFI=$(checkWITF 'eth0')"

diagnostic > /tmp/diagnostic
FVT6_DIAG() { echo "${1}=$(cat /tmp/diagnostic | grep -i ${1} | egrep -o '(OK|KO)')"; }

FVT6_LOG "$(FVT6_DIAG 'GPS')"
FVT6_LOG "$(FVT6_DIAG 'MMC')"
FVT6_LOG "$(FVT6_DIAG 'BLDC')"
FVT6_LOG "$(FVT6_DIAG 'P7MU')"
FVT6_LOG "$(FVT6_DIAG 'MS5607')"
FVT6_LOG "$(FVT6_DIAG 'MPU6050')"
FVT6_LOG "$(FVT6_DIAG 'AK8963')"
FVT6_LOG "$(FVT6_DIAG 'P7US')"
FVT6_LOG "$(FVT6_DIAG 'MT9v117')"
FVT6_LOG "$(FVT6_DIAG 'MT9f002')"
# Pinout test is not compiled in FVT6 anymore
#FVT6_LOG "$(FVT6_DIAG 'HCAM_PINOUT')"
FVT6_LOG ""

FVT6_LOG "[Global Status]"
FVT6_LOG "FWStatus=NOTTESTED"

# Copy the log file to the virtual USB key
/bin/mount_imgdisk.sh ${ARDRONE3_USBDISKIMG_PATH} ${ARDRONE3_USBDISKIMG_MOUNT_PATH} "Bebop_Drone" | logger -s -t "FVT6" -p user.info
cp ${FVT6TMPFILE} ${ARDRONE3_USBDISKIMG_MOUNT_PATH}/fvt6.txt
/bin/umount_imgdisk.sh ${ARDRONE3_USBDISKIMG_MOUNT_PATH} | logger -s -t "FVT6" -p user.info
# Save a copy in /factory
cp ${FVT6TMPFILE} /factory/FVT6.txt
# Save it with its final name, preventing its regeneration until next FVT6 flash
mv ${FVT6TMPFILE} ${FVT6FILE}
# Remove the trigger (ie. never regenerate FVT6 log until next FVT6 flashing)
rm ${FVT6TRIGGER}
sync

FVT6_EXIT "Done"
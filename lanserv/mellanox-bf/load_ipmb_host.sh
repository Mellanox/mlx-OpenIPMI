#!/bin/bash

# Check if the i2cbus parameter is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <i2cbus> <action>"
  echo "Actions: load, remove"
  exit 1
fi

i2cbus=$1
action=$2

# By default, 0x11 is the BF slave address at which
# the ipmb_host device is registered.
# The i2c slave backends have their own address
# space. So, add 0x1000 to the original address.
# The following addresses are all in hex.
IPMB_HOST_ADD=0x1011

# By default, the ipmb_host driver communicates with
# a client at address 0x10.
# ipmb_host driver is not installed in all images
IPMB_HOST_CLIENTADDR=0x10

I2C_NEW_DEV=/sys/bus/i2c/devices/i2c-$i2cbus/new_device
I2C_DEL_DEV=/sys/bus/i2c/devices/i2c-$i2cbus/delete_device
# The IPMB_HOST_FLAG is created if the ipmb-host driver is loaded by the BMC
# using ipmi oem command: ipmitool -I ipmb raw 0x2e 0x2 0x47 0x16 0x0
# This flag is cleared after reboot the DPU.
IPMB_HOST_FLAG=/run/emu_param/ipmb_host_driver_loaded
# The IPMB_RETRY_FLAG is created if the host driver is needed to be reloaded.
# This flag is cleared after reboot the DPU or successful retry.
IPMB_RETRY_FLAG=/run/emu_param/ipmb_host_driver_retry
# Define the retry interval increase every one minute

load_ipmb_host() {
	modprobe ipmb_host slave_add=$IPMB_HOST_CLIENTADDR
	echo ipmb-host $IPMB_HOST_ADD > $I2C_NEW_DEV
}

remove_ipmb_host() {
	echo $IPMB_HOST_ADD > $I2C_DEL_DEV
	rmmod ipmb_host
}

check_ipmb_connection() {
	# Check IPMI MC info and redirect output to /dev/null
	ipmitool mc info > /dev/null 2>&1
	# If ipmitool command fails
	if [ $? -ne 0 ]; then
		# If IPMB retry flag file exists, read and increment the retry count
		if [ -f $IPMB_RETRY_FLAG ]; then
			retries=$(cat $IPMB_RETRY_FLAG)
			retries=$((retries + 1))
		else
		# If the file does not exist, start with the first retry
			retries=1
		fi
        # Update the retry count in the file
		echo $retries > $IPMB_RETRY_FLAG
		remove_ipmb_host
	else
		# Remove IPMB retry flag file if ipmitool command succeeds
		rm -f $IPMB_RETRY_FLAG
	fi
}

if [ "$action" == "load" ]; then
	# Function to load IPMB host with retry mechanism
	if [ ! -f $IPMB_HOST_FLAG ]; then
		touch $IPMB_HOST_FLAG
		# Avoid the driver is loaded at same time by BMC and script
		sleep 15
		load_ipmb_host
		check_ipmb_connection
		# Avoid the driver is loaded at same time by BMC and script
		sleep 15
		rm -f $IPMB_HOST_FLAG
	fi
elif [ "$action" == "remove" ]; then
	if [ -f $IPMB_HOST_FLAG ]; then
		sleep 10
		rm -f $IPMB_HOST_FLAG
	fi
fi

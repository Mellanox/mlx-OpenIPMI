#!/bin/sh

# Arguments passed to this script:
# $1 time interval for executing set_emu_param.sh in seconds.
# $2 is set to "Bluewhale" if it is a BlueWhale board.
# $3 should be set to 1 if IPMB is supported.
# $4 should be set to the OOB ip address if supported.
# example: "192.168.101.2". If OOB is not supported, $4
# should be set to "0".
# $5 should be "YES" if external DDRs are supported.

# This timer is used to update certain data based on a timer.
# Certain FRU data for example, should be updated every hour.
# This is needed in the case where customers
# need to retrieve FRU data 16 or 32 bytes at
# a time.
# set_emu_param.service executes set_emu_param.sh
# every 3s, so we need to execute that script 1200
# times (0x4b0 in hex) per hour then update the desired FRUs.
ipmi_init_timer=0x4b0
ipmi_update_timer=0x4af

while /bin/true; do
	/usr/bin/set_emu_param.sh $2 $3 $4 $5 $ipmi_update_timer

	((ipmi_update_timer=ipmi_update_timer-1))

	if (( $ipmi_update_timer == 0 )); then
		# reset the timer
		ipmi_update_timer=$ipmi_init_timer
	fi

	sleep $1
done

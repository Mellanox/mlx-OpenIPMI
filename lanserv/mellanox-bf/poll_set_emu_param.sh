#! /bin/sh

# Arguments passed to this script:
# $1 time interval for executing set_emu_param.sh in seconds.
# $2 is set to "Bluewhale" if it is a BlueWhale board.
# $3 should be set to 1 if IPMB is supported.
# $4 should be set to the OOB ip address if supported.
# example: "192.168.101.2". If OOB is not supported, $4
# should be set to "0".
cp 

while /bin/true; do
	/usr/bin/set_emu_param.sh $2 $3 $4
	sleep $1
done

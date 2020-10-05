#! /bin/sh

# Arguments passed to this script:
# $1 time interval for executing set_emu_param.sh in seconds.
# $2 is set to "Bluewhale" if it is a BlueWhale board.
# $3 should be set to 1 if IPMB is supported.

while /bin/true; do
	/usr/bin/set_emu_param.sh $2 $3
	sleep $1
done

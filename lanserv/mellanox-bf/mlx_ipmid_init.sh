#! /bin/sh

# This wrapper file is passed as ExecStartPre in
# mlx_ipmid.service to initialize emulator data before
# starting ipmi_sim. Service logs are sent to journald.

# Arguments passed to this script:
# $1 is set to "Bluewhale" if it is a BlueWhale board.
# $2 should be set to 1 if IPMB is supported.
# $3 should be set to the OOB ip address if supported.
# example: "192.168.101.2". If OOB is not supported, $4
# should be set to "0".
# $4 should be set to 1 if external ddrs are supported.
# $5 time interval for executing set_emu_param.sh in seconds.

/usr/bin/set_emu_param.sh $1 $2 $3 $4 $5 $6 $7

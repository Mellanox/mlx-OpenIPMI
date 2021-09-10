#! /bin/sh

# This wrapper file is passed as ExecStartPre in
# mlx_ipmid.service because the syntax:
# StandardOutput=append:...
# is only supported in systemd version >= 240.
# Some linux distros (CentOS8.2 for example), support
# older versions of systemd.
# So use StandardOutput=file:...
# The downside of this is that the whole log files
# contents are overwritten each time the service is
# restarted. The file needs to be deleted every time.

# Arguments passed to this script:
# $1 is set to "Bluewhale" if it is a BlueWhale board.
# $2 should be set to 1 if IPMB is supported.
# $3 should be set to the OOB ip address if supported.
# example: "192.168.101.2". If OOB is not supported, $4
# should be set to "0".
# $4 should be set to 1 if external ddrs are supported.
# $5 time interval for executing set_emu_param.sh in seconds.

rm -f /run/log/mlx_ipmid.log
/usr/bin/set_emu_param.sh $1 $2 $3 $4 $5

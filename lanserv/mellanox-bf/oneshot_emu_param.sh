#!/bin/sh

# $1 BF_FAMILY
# $2 SUPPORT_IPMB
# $3 OOB_IP
# $4 BF_PLAT

BF1_PLATFORM_ID=0x00000211
BF2_PLATFORM_ID=0x00000214

if [ "$4" = $BF1_PLATFORM_ID ]; then
	ln -s /usr/bin/set_emu_param_bf1.sh /usr/bin/set_emu_param.sh
	ln -s /etc/ipmi/mlx-bf1.emu /etc/ipmi/mlx-bf.emu
	ln -s /var/ipmi_sim/mellanox/sdr.30.main.bf1 /var/ipmi_sim/mellanox/sdr.30.main
elif [ "$4" = $BF2_PLATFORM_ID ]; then
	ln -s /usr/bin/set_emu_param_bf2.sh /usr/bin/set_emu_param.sh
	ln -s /etc/ipmi/mlx-bf2.emu /etc/ipmi/mlx-bf.emu
	ln -s /var/ipmi_sim/mellanox/sdr.30.main.bf2 /var/ipmi_sim/mellanox/sdr.30.main
else
	echo "Unsupported Platform"
	exit 1
fi

/usr/bin/set_emu_param.sh $1 $2 $3

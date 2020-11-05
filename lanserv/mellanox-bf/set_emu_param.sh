#!/bin/sh

# To view whether this daemon failed to retrieve
# certain information needed by IPMI, use:
# journalctl -u set_emu_param

EMU_PARAM_DIR=/var/emu_param

# Data that is needed to build the .emu file
# will be provided in the emu_param directory
EMU_FILE_PATH=/etc/ipmi/mlx-bf.emu

if [ ! -d $EMU_PARAM_DIR ]; then
	mkdir $EMU_PARAM_DIR
fi

if [ ! -s  $EMU_PARAM_DIR/ip_addresses ]; then
	touch $EMU_PARAM_DIR/ip_addresses
fi

#############################################
# The ipmb_dev_int driver is already loaded #
# by default in the install image. This     #
# script instantiates the IPMB device.      #
#############################################

# This timer is used to update the FRUs
# once every hour. It also informs the user
# how much time is left before the next FRU
# update.
# This is needed in the case where customers
# need to retrieve FRU data 16 or 32 bytes at
# a time.
# set_emu_param.service executes set_emu_param.sh
# every 3s, so we need to execute that script 1200
# times before an hour has passed and we can update
# the desired FRUs. 0x4b0 is the hex for 1200.
fru_timer=0x4b0
if [ ! -s $EMU_PARAM_DIR/ipmb_update_timer ]; then
         echo $fru_timer > $EMU_PARAM_DIR/ipmb_update_timer
         t=$fru_timer
else
         t=$(cat $EMU_PARAM_DIR/ipmb_update_timer)
         if [ "$t" = "0x000" ]; then
                 echo $fru_timer > $EMU_PARAM_DIR/ipmb_update_timer
         else
                m=$(($t - 1))
                printf "0x%03X\n" $m > $EMU_PARAM_DIR/ipmb_update_timer
         fi
fi

# By default, 0x30 is the BF slave address at which
# the ipmb_dev_int device is registered.
# By default, 0x11 is the BF slave address at which
# the ipmb_host device is registered.
# The i2c slave backends have their own address
# space. So, add 0x1000 to the original address.
# The following addresses are all in hex.
IPMB_DEV_INT_ADD=0x1030
IPMB_HOST_ADD=0x1011

# By default, the ipmb_host driver communicates with
# a client at address 0x10.
IPMB_HOST_CLIENTADDR=0x10

I2C2_NEW_DEV=/sys/bus/i2c/devices/i2c-2/new_device
I2C2_DEL_DEV=/sys/bus/i2c/devices/i2c-2/delete_device

is_bluewhale=$1
support_ipmb=$2
oob_ip=$3

if [ "$is_bluewhale" = "Bluewhale" ] || [ "$support_ipmb" = "1" ]; then
	# Instantiate the ipmb-dev device
	if [ ! -c "/dev/ipmb-2" ]; then
		echo ipmb-dev $IPMB_DEV_INT_ADD > $I2C2_NEW_DEV
	fi

	if ! grep -q "ipmb-2" /etc/ipmi/mlx-bf.lan.conf; then
		echo "  ipmb 2 ipmb_dev_int /dev/ipmb-2" >> /etc/ipmi/mlx-bf.lan.conf
	fi

	# load the ipmb_host driver
	if [ ! "$(lsmod | grep ipmi_msghandler)" ]; then
		modprobe ipmi_msghandler
	fi
	if [ ! "$(lsmod | grep ipmi_devintf)" ]; then
		modprobe ipmi_devintf
	fi
	if [ ! "$(lsmod | grep ipmb_host)" ]; then
		modprobe ipmb_host slave_add=$IPMB_HOST_CLIENTADDR
		echo ipmb-host $IPMB_HOST_ADD > $I2C2_NEW_DEV
	fi
fi #support_ipmb

if [ ! "$oob_ip" = "0" ]; then
	if ! grep -q "startlan 2" /etc/ipmi/mlx-bf.lan.conf; then
		cat <<- EOF >> /etc/ipmi/mlx-bf.lan.conf
		  startlan 2
		    addr $oob_ip 623
		    priv_limit admin
		    guid a123456789abcdefa123456789abcdef
		  endlan
		EOF
	fi
fi #oob_ip

###############################
# Collect sensor and fru data #
###############################

# The following addresses are all in hex.
SPD0_I2C_ADDR=50
SPD1_I2C_ADDR=51
SPD2_I2C_ADDR=52
SPD3_I2C_ADDR=53

SPDS_ADDR="$SPD0_I2C_ADDR $SPD1_I2C_ADDR $SPD2_I2C_ADDR $SPD3_I2C_ADDR"

I2C1_DEVPATH=/sys/bus/i2c/devices/i2c-1/new_device

remove_sensor() {
	rm -f $EMU_PARAM_DIR/$1
}

add_fru() {
	if [ $(cat $EMU_PARAM_DIR/$1"_filelen") -gt 0 ]; then
		echo "mc_add_fru_data 0x30 $2 $(cat $EMU_PARAM_DIR/$1"_filelen") file 0 \"$EMU_PARAM_DIR/$1\"" >> $EMU_FILE_PATH
	fi
}

grep_for_dimm_temp() {
	# In Yocto, grep for the "DDR4 Temp" string, since we use a customized sensors.conf file.
	# But in CentOS, libsensors is yum installed so grep for the default "temp1:" string.
	grep "DDR4 Temp:" $EMU_PARAM_DIR/$1_info > /tmp/DDR4_str
	grep "temp1:" $EMU_PARAM_DIR/$1_info > /tmp/temp1_str
	if [ -s /tmp/DDR4_str ]; then
		cat /tmp/DDR4_str | cut -d "+" -f 2 | cut -d "." -f 1 > $EMU_PARAM_DIR/$1
	elif [ -s /tmp/temp1_str ]; then
		cat /tmp/temp1_str | cut -d "+" -f 2 | cut -d "." -f 1 > $EMU_PARAM_DIR/$1
	else
		echo WARNING: Unable to find DIMM temp
	fi
}

# $1 is the mst cable name
# $2 is the output file name
get_qsfp_eeprom_data() {
	# From SFF8636 spec, memory map is arranged into a single lower page
	# address space of 128 bytes and multiple address pages of 128 bytes each.
	# Only lower and upper page 0 is required and hence reported.
	# Get 256 bytes of raw hex data from QSFP EEPROM at page 0 and offset 0.
	mlxcables -d $1 --print_raw -r -p 0 -o 0 -l 256 -b 32 > /tmp/temp1

	# strip the raw hex data from byte id
	sed s/[0-9][0-9][0-9]:// /tmp/temp1 > /tmp/temp2

	# Put all data in one line and rm space between bytes,
	# then convert it to a binary file.
	cat /tmp/temp2 | tr -d ' ' | tr -d '\n' | perl -lpe '$_=pack"H*",$_' > /tmp/temp1

	# Make sure binary data packed is 256 bytes
	dd if=/tmp/temp1 of=$EMU_PARAM_DIR/$2 bs=1 skip=0 count=256
	wc -c $EMU_PARAM_DIR/$2 | cut -f 1 -d " " > $EMU_PARAM_DIR/$2"_filelen"

	rm /tmp/temp1 /tmp/temp2
}

# $1 is the mst cable name
# $2 is the output file name
get_qsfp_temp() {
	temp=$(mlxcables -d $1 | grep Temperature | cut -f 2 -d ":" | cut -f 2 -d " ")
	if [ "$temp" != "N/A" ]; then
		echo $temp > $EMU_PARAM_DIR/$2
	else
		remove_sensor "$2"
	fi
}


###########################################
# Get connectX network interfaces information
#
# $1 is the original network name
###########################################
get_connectx_net_info() {
	# In the BlueWhale and other similar designs,
	# udev renames the interfaces to enp*f* while on
	# the SNIC, the connectX interfaces are renamed p0 and p1
	eth=$(ifconfig -a | grep "enp.*f$1" | cut -f 1 -d " " | cut -f 1 -d ":")
	if [ -z $eth ]; then
		eth="p$1"
	fi

	echo "LAN Interface:" > $EMU_PARAM_DIR/eth$1
	ifconfig $eth >> $EMU_PARAM_DIR/eth$1 2>/dev/null
	if [ ! $? -eq 0 ]; then
		# if this interface is not supported, delete FRU file
		rm $EMU_PARAM_DIR/eth$1 2>/dev/null
		return
	fi
	ethtool $eth | grep -i "speed" >> $EMU_PARAM_DIR/eth$1

	# Get gateway
	ip r | grep default | grep "dev $eth" >> $EMU_PARAM_DIR/eth$1

	isdhcp=false

	# Check if IPv4 address is assigned
	ifconfig $eth | grep "inet addr:"
	if [ $? -eq 0 ]; then

		# On Yocto and Ubuntu
		file=$(networkctl status -a  | grep $eth -A 2 | grep "Network File" | cut -d ":" -f 2)
		grep "DHCP=yes" $file > /dev/null 2>&1
		if [ $? -eq 0 ]; then
			isdhcp=true
		fi

		# On CentOS
		grep "BOOTPROTO=dhcp" /etc/sysconfig/network-scripts/ifcfg-$eth > /dev/null 2>&1
		if [ $? -eq 0 ]; then
			isdhcp=true
		fi

		if $isdhcp ; then
			echo "IPv4 Address Origin: DHCP" >> $EMU_PARAM_DIR/eth$1
		else
			echo "IPv4 Address Origin: Static" >> $EMU_PARAM_DIR/eth$1
		fi
	fi

	isdhcp=false

	# Check if IPv6 address is assigned and is not a link local address
	ifconfig $eth | grep "inet6 addr:" | grep -v "fe80"
	if [ $? -eq 0 ]; then

		# On Yocto and Ubuntu
		file=$(networkctl status -a  | grep $eth -A 2 | grep "Network File" | cut -d ":" -f 2)
		grep "DHCP=yes" $file > /dev/null 2>&1
		if [ $? -eq 0 ]; then
			isdhcp=true
		fi

		# On CentOS
		grep "DHCPV6C" /etc/sysconfig/network-scripts/ifcfg-$eth > /dev/null 2>&1
		if [ $? -eq 0 ]; then
			isdhcp=true
		fi

		if $isdhcp ; then
			echo "IPv6 Address Origin: DHCP" >> $EMU_PARAM_DIR/eth$1
		else
			echo "IPv6 Address Origin: Static" >> $EMU_PARAM_DIR/eth$1
		fi
	fi

	ethtool -S $eth | grep prio >> $EMU_PARAM_DIR/eth$1
	echo "End LAN Interface" >> $EMU_PARAM_DIR/eth$1

	# Pad the file with spaces in case the size of the temp files increases
	truncate -s 3000 $EMU_PARAM_DIR/eth$1
}


####################################################
#               Get SPDs' information              #
####################################################
if [ ! "$(lsmod | grep ee1004)" ]; then
	modprobe ee1004
fi

if [ "$(lsmod | grep ee1004)" ]; then
	# Up to 4 SPDs can be connected to I2C bus 1. To
	# read information contained in those SPDs, the ee1004
	# driver needs to be loaded, and the devices need to
	# be instantiated.
	# Note that this script should be kept consistent with
	# the board design. So if the I2C address of the SPDs
	# is changed, the script needs to be changed as well.
	for i in $SPDS_ADDR
	do
		if [ ! -d "/sys/bus/i2c/devices/1-00$i" ]; then
			if [ $(i2cget -y -f 1 0x$i 2>/dev/null) ]; then
				echo ee1004 0x$i > $I2C1_DEVPATH
			fi
		fi
	done
fi

###############################################
#           Get DIMMs' temperature            #
###############################################
if [ ! "$(lsmod | grep jc42)" ]; then
	modprobe jc42

	if [ "$(lsmod | grep jc42)" ]; then
		sensors -s
	fi
fi

if [ "$(lsmod | grep jc42)" ]; then
	# jc42 driver needs to be loaded for the following:
	sensors > $EMU_PARAM_DIR/ddr_temps

	sed -n '/jc42-i2c-1-18/,/^$/p' $EMU_PARAM_DIR/ddr_temps > $EMU_PARAM_DIR/ddr0_0_temp_info
	sed -n '/jc42-i2c-1-19/,/^$/p' $EMU_PARAM_DIR/ddr_temps > $EMU_PARAM_DIR/ddr0_1_temp_info
	sed -n '/jc42-i2c-1-1a/,/^$/p' $EMU_PARAM_DIR/ddr_temps > $EMU_PARAM_DIR/ddr1_0_temp_info
	sed -n '/jc42-i2c-1-1b/,/^$/p' $EMU_PARAM_DIR/ddr_temps > $EMU_PARAM_DIR/ddr1_1_temp_info

	# It is safe to assume that the dimms temperature would always be a positive value.
	# If the ddr is not present in the system, we set the temp value to 0, otherwise
	# the ipmi daemon will complain about polling a file that's empty.
	if [ -s $EMU_PARAM_DIR/ddr0_0_temp_info ]; then
		grep_for_dimm_temp "ddr0_0_temp"
	else
		remove_sensor "ddr0_0_temp"
	fi

	if [ -s $EMU_PARAM_DIR/ddr0_1_temp_info ]; then
		grep_for_dimm_temp "ddr0_1_temp"
	else
		remove_sensor "ddr0_1_temp"
	fi

	if [ -s $EMU_PARAM_DIR/ddr1_0_temp_info ]; then
		grep_for_dimm_temp "ddr1_0_temp"
	else
		remove_sensor "ddr1_0_temp"
	fi

	if [ -s $EMU_PARAM_DIR/ddr1_1_temp_info ]; then
		grep_for_dimm_temp "ddr1_1_temp"
	else
		remove_sensor "ddr1_1_temp"
	fi
fi


####################################
#         Get the BF's temp        #
####################################
if [ ! -d /dev/mst ]; then
	mst start
fi
temp=$(mget_temp -d /dev/mst/mt*_pciconf0)

if [ -z "$temp" ]; then
	remove_sensor "bluefield_temp"
else
	echo $temp > $EMU_PARAM_DIR/bluefield_temp
fi


#############################################################
#   Get NIC VID, SVID, DID, SDID and get QSFP link status   #
#############################################################
# To get the NIC VID, SVID, DID and SDID, we use the pci dev
# info (lspci). The pci bus number is set by the OS and is
# likely to change if someone adds a card in the pci slot.
# So we use the pci device class number to determine the bdf
# for the NIC pci. The NIC card can be associated with device
# class 0200 if it is connected via pcie or class 0207 if it
# is connected via infiniband.
lspci -n | grep 0200 | cut -f 1 -d " " > $EMU_PARAM_DIR/eth_bdfs.txt
lspci -n | grep 0207 | cut -f 1 -d " " > $EMU_PARAM_DIR/ib_bdfs.txt

if [ ! -s $EMU_PARAM_DIR/eth_bdfs.txt ] && [ ! -s $EMU_PARAM_DIR/ib_bdfs.txt ]; then
	# No connection to the QSFPs so links are considered down
	# bit[0]=1 indicates links are up
	# bit[1]=2 indicates links are down

	cat <<-EOF > $EMU_PARAM_DIR/nic_pci_dev_info
	Unable to get NIC PCI device info since the network ports are not configured.
	EOF

	echo 2 > $EMU_PARAM_DIR/p0_link
	echo 2 > $EMU_PARAM_DIR/p1_link
else
	bdf_eth=$(head -n 1 $EMU_PARAM_DIR/eth_bdfs.txt)
	bdf_ib=$(head -n 1 $EMU_PARAM_DIR/ib_bdfs.txt)

	lspci -n -v -m -s $bdf_eth > $EMU_PARAM_DIR/nic_pci_dev_info 2>/dev/null
	lspci -n -v -m -s $bdf_ib >> $EMU_PARAM_DIR/nic_pci_dev_info 2>/dev/null

	if [ -s $EMU_PARAM_DIR/eth_bdfs.txt ]; then
		while read bdf; do
			link_status=$(cat /sys/bus/pci/devices/0000\:$bdf/net/e*/operstate)
			func=$(echo $bdf | cut -f 1 -d " " | cut -f 2 -d ".")

			if [ "$link_status" = "up" ]; then
				echo 1 > $EMU_PARAM_DIR/p$func"_link"
			else
				echo 2 > $EMU_PARAM_DIR/p$func"_link"
			fi
		done <$EMU_PARAM_DIR/eth_bdfs.txt
	fi

	if [ -s $EMU_PARAM_DIR/ib_bdfs.txt ]; then
		while read bdf; do
			func=$(echo $bdf | cut -f 1 -d " " | cut -f 2 -d ".")
			link_status=$(cat /sys/class/net/ib$func/operstate)

			if [ "$link_status" = "up" ]; then
				echo 1 > $EMU_PARAM_DIR/p$func"_link"
			else
				echo 2 > $EMU_PARAM_DIR/p$func"_link"
			fi
		done <$EMU_PARAM_DIR/ib_bdfs.txt
	fi
fi

wc -c $EMU_PARAM_DIR/nic_pci_dev_info | cut -f 1 -d " " > $EMU_PARAM_DIR/nic_pci_dev_info_filelen

rm $EMU_PARAM_DIR/eth_bdfs.txt
rm $EMU_PARAM_DIR/ib_bdfs.txt


###################################
#          Get FW info            #
###################################
#
# This directory exists for both infiniband and ethernet.
# The reason for that is RoCE which implements the infiniband protocol
# (RDMA), with ethernet as the link layer instead of IB.
#
if [ -d /sys/class/infiniband/mlx*_0 ]; then
	port=0
elif [ -d /sys/class/infiniband/mlx*_1 ]; then
	port=1
else
	port=-1
fi

if [ "$port" = "-1" ]; then
	cat <<- EOF > $EMU_PARAM_DIR/fw_info
	Unable to get fw info since the network ports are not configured.
	EOF
else
	if [ $bdf_eth ]; then
		bdf=$bdf_eth
	elif [ $bdf_ib ]; then
		bdf=$bdf_ib
	else
		bdf=NULL
	fi

	if [ "$bdf" != "NULL" ]; then
		cat <<- EOF > $EMU_PARAM_DIR/fw_info
		$(/opt/mlnx/scripts/bfver | sed '1d')
		BlueField OFED Version: $(ofed_info -s | sed 's/.$//')
		connectx_fw_ver: $(cat /sys/class/infiniband/mlx*_$port/fw_ver)
		board_id: $(cat /sys/class/infiniband/mlx*_$port/board_id)
		node_guid: $(cat /sys/class/infiniband/mlx*_$port/node_guid)
		sys_image_guid: $(cat /sys/class/infiniband/mlx*_$port/sys_image_guid)
		vpd info:
		$(lspci -vvv -s $bdf | sed -n "/Vital/,/End/p")
		EOF
	else
		cat <<- EOF > $EMU_PARAM_DIR/fw_info
		Unable to get fw info since the network ports are not configured.
		EOF
	fi
fi
wc -c $EMU_PARAM_DIR/fw_info | cut -f 1 -d " " > $EMU_PARAM_DIR/fw_info_filelen


########################################################################
#       Get QSFP ports temperature and QSFP EEPROM data aka VPDs       #
########################################################################
#
# If a port is not connected or if its temperature is reported as
# "N/A" by FW, then the ipmitool command will show a value of -128 deg.
# This is the equivalent of an invalid temperature reading.
# The mlxcables command reports a temperature as N/A if the cable is not
# an optics cable with a capacity of 25G or 100G.
#

mst cable add

if [ -f /dev/mst/*cable_0 ]; then
	cable_0=$(ls /dev/mst/*cable_0 | cut -f 4 -d "/")
else
	cable_0=""
fi

if [ -f /dev/mst/*cable_1 ]; then
	cable_1=$(ls /dev/mst/*cable_1 | cut -f 4 -d "/")
else
	cable_1=""
fi

if [ $cable_0 ]; then

	### Get the temperature for QSFP port0 ###
	get_qsfp_temp $cable_0 "p0_temp"

	#### Get QSFP EEPROM data ###
	get_qsfp_eeprom_data $cable_0 "qsfp0_eeprom"

else
	remove_sensor "p0_temp"
	echo 0 > $EMU_PARAM_DIR/qsfp0_eeprom_filelen
fi

if [ $cable_1 ]; then

	### Get the temperature for QSFP port1 ###
	get_qsfp_temp $cable_1 "p1_temp"

	#### Get QSFP EEPROM data ###
	get_qsfp_eeprom_data $cable_1 "qsfp1_eeprom"

else
	remove_sensor "p1_temp"
	echo 0 > $EMU_PARAM_DIR/qsfp1_eeprom_filelen
fi

# add trailing spaces to each line so that the dimms_ce_ue FRU can be updated
# when the number of errors increases.
edac-util -rfull > /tmp/dimms_ce_ue
awk '{printf "%-100s\n", $0}' /tmp/dimms_ce_ue > $EMU_PARAM_DIR/dimms_ce_ue


# Update eth0 and eth1 files every minute
# 1 mn = 60 sec = 3 sec * 20
if [ $(( $t % 20 )) -eq 0 ]; then
	# Get 100G network interfaces information
	get_connectx_net_info "0"
	get_connectx_net_info "1"
fi


# We don't want to update the FRU data as often as the temp values
# or the link status for 2 reasons:
# - The FRUs not really susceptible to change unless the user makes changes directly to HW
# - Some users need enough time to retrieve FRUs via ipmitool raw command.
# So only update it once every hour.
if [ "$t" = "$fru_timer" ]; then

	###################################
	#        Get the cpu info         #
	###################################
	lscpu > $EMU_PARAM_DIR/cpuinfo
	cat /proc/cpuinfo >> $EMU_PARAM_DIR/cpuinfo
	wc -c $EMU_PARAM_DIR/cpuinfo | cut -f 1 -d " " > $EMU_PARAM_DIR/cpuinfo_filelen


	##########################################
	#          Get EMMC info                 #
	##########################################

	# Collect data about emmc size and its partitions
	fdisk -l /dev/mmcblk0 > $EMU_PARAM_DIR/emmc_info
	echo >> $EMU_PARAM_DIR/emmc_info

	# Collect data about partitions usage
	mount | grep mmc > $EMU_PARAM_DIR/mmc_partitions

	if [ ! -s $EMU_PARAM_DIR/mmc_partitions ]; then
		echo There is no mounted EMMC partition >> $EMU_PARAM_DIR/emmc_info
	else
		while IFS= read -r line
		do
			devf=$(echo $line | cut -d " " -f 1)
			echo "emmc partition: $devf" >> $EMU_PARAM_DIR/emmc_info
			mount_on=$(echo $line | cut -d " " -f 3)
			df -k $mount_on >> $EMU_PARAM_DIR/emmc_info
			echo >> $EMU_PARAM_DIR/emmc_info
		done < $EMU_PARAM_DIR/mmc_partitions
	fi

	echo StartBinary >> $EMU_PARAM_DIR/emmc_info

	# The EMMC binary CID, CSD and EXT CSD data is sent in a concatenated
	# format.
	# bit[0] of the CID and CSD regs should always be 1 according to the
	# JEDEC spec. So, if the CID or CSD registers are unreadable, the
	# script will pass 128 zero bits. bit[0]=0 would indicate that the
	# CID/CSD content is not readable.
	# The last bit of the EXT CSD reg should always be 0 according to the
	# JEDEC spec. So if the EXT CSD is unreadable, the script will pass
	# 512 one bits. bit[0]=1 would indicate that the EXT CSD is not readable.

	# CID binary data
	CID=`find /sys/devices -name 'cid'| grep mmc| xargs cat| sed 's/.\{2\}/& /g'`
	if [ -z "$CID" ]; then
		CID=`printf '00 %.0s' $(seq 1 16)`
	fi
	echo $CID |tr -d ' ' | tr -d '\n' | perl -lpe '$_=pack"H*",$_' > /tmp/temp
	dd if=/tmp/temp of=$EMU_PARAM_DIR/emmc_cid bs=1 skip=0 count=16

	# CSD binary data
	CSD=`find /sys/devices -name 'csd'| grep mmc| xargs cat| sed 's/.\{2\}/& /g'`
	if [ -z "$CSD" ]; then
		CSD=`printf '00 %.0s' $(seq 1 16)`
	fi
	echo $CSD |tr -d ' ' | tr -d '\n' | perl -lpe '$_=pack"H*",$_' > /tmp/temp
	dd if=/tmp/temp of=$EMU_PARAM_DIR/emmc_csd bs=1 skip=0 count=16

	# Ext CSD binary data
	EXTCSD=`cat '/sys/kernel/debug/mmc0/mmc0:0001/ext_csd' | sed 's/.\{2\}/& /g'`
	if [ -z "$EXTCSD" ]; then
		EXTCSD=`printf 'ff %.0s' $(seq 1 16)`
	fi
	echo $EXTCSD |tr -d ' ' | tr -d '\n' | perl -lpe '$_=pack"H*",$_' > /tmp/temp
	dd if=/tmp/temp of=$EMU_PARAM_DIR/emmc_extcsd bs=1 skip=0 count=512

	rm /tmp/temp

	# Concatenate the binaries together
	cat $EMU_PARAM_DIR/emmc_cid $EMU_PARAM_DIR/emmc_csd $EMU_PARAM_DIR/emmc_extcsd >> $EMU_PARAM_DIR/emmc_info

	wc -c $EMU_PARAM_DIR/emmc_info | cut -f 1 -d " " > $EMU_PARAM_DIR/emmc_info_filelen


	#############################################
	# Add FRU parameters to the mlx-bf.emu file #
	#############################################

	# We need to know the length of the files before passing that value to
	# mc_add_fru_data. If we pass a length that is larger than the file,
	# the read fails and the output for reading the FRU is invalid.
	DDR00_SPD_PATH=/sys/bus/i2c/drivers/ee1004/1-0050/eeprom
	DDR01_SPD_PATH=/sys/bus/i2c/drivers/ee1004/1-0051/eeprom
	DDR10_SPD_PATH=/sys/bus/i2c/drivers/ee1004/1-0052/eeprom
	DDR11_SPD_PATH=/sys/bus/i2c/drivers/ee1004/1-0053/eeprom

	sed -i '/DELETE AT START/Q' $EMU_FILE_PATH
	echo "#DELETE AT START" >> $EMU_FILE_PATH

	echo "mc_add_fru_data 0x30 0 6 file 0 \"$EMU_PARAM_DIR/ipmb_update_timer\"" >> $EMU_FILE_PATH

	add_fru "fw_info" 1
	add_fru "nic_pci_dev_info" 2
	add_fru "cpuinfo" 3

	if [ -s $DDR00_SPD_PATH ]; then
		wc -c $DDR00_SPD_PATH | cut -f 1 -d " " > $EMU_PARAM_DIR/ddr0_0_spd_filelen
		echo "mc_add_fru_data 0x30 4 $(cat $EMU_PARAM_DIR/ddr0_0_spd_filelen) file 0 \"$DDR00_SPD_PATH\"" >> $EMU_FILE_PATH
	fi
	if [ -s $DDR01_SPD_PATH ]; then
		wc -c $DDR01_SPD_PATH | cut -f 1 -d " " > $EMU_PARAM_DIR/ddr0_1_spd_filelen
		echo "mc_add_fru_data 0x30 5 $(cat $EMU_PARAM_DIR/ddr0_1_spd_filelen) file 0 \"$DDR01_SPD_PATH\"" >> $EMU_FILE_PATH
	fi
	if [ -s $DDR10_SPD_PATH ]; then
		wc -c $DDR10_SPD_PATH | cut -f 1 -d " " > $EMU_PARAM_DIR/ddr1_0_spd_filelen
		echo "mc_add_fru_data 0x30 6 $(cat $EMU_PARAM_DIR/ddr1_0_spd_filelen) file 0 \"$DDR10_SPD_PATH\"" >> $EMU_FILE_PATH
	fi
	if [ -s $DDR11_SPD_PATH ]; then
		wc -c $DDR11_SPD_PATH | cut -f 1 -d " " > $EMU_PARAM_DIR/ddr1_1_spd_filelen
		echo "mc_add_fru_data 0x30 7 $(cat $EMU_PARAM_DIR/ddr1_1_spd_filelen) file 0 \"$DDR11_SPD_PATH\"" >> $EMU_FILE_PATH
	fi

	wc -c $EMU_PARAM_DIR/dimms_ce_ue | cut -f 1 -d " " > $EMU_PARAM_DIR/dimms_ce_ue_filelen
	wc -c $EMU_PARAM_DIR/eth0 | cut -f 1 -d " " > $EMU_PARAM_DIR/eth0_filelen
	wc -c $EMU_PARAM_DIR/eth1 | cut -f 1 -d " " > $EMU_PARAM_DIR/eth1_filelen

	add_fru "emmc_info" 8
	add_fru "qsfp0_eeprom" 9
	add_fru "qsfp1_eeprom" 10
	add_fru "dimms_ce_ue" 12
	if [ -s $EMU_PARAM_DIR/eth0_filelen ]; then
		add_fru "eth0" 13
	fi
	if [ -s $EMU_PARAM_DIR/eth1_filelen ]; then
		add_fru "eth1" 14
	fi

	mlxreg -d /dev/mst/mt*_pciconf0 --reg_name MDIR --get | awk '{if(NR>2)print}' \
	       	| grep device | cut -d "x" -f 2 | tr -d '\n' > $EMU_PARAM_DIR/bf_uid
	if [ ! -s $EMU_PARAM_DIR/bf_uid ]; then
		cat <<- EOF > $EMU_PARAM_DIR/bf_uid
		Failed to retrieve the BF UID. Please update to FW version xx.28.1068 or higher and
		to MFT version 4.15.0-104 or higher.
		EOF
	fi
	wc -c $EMU_PARAM_DIR/bf_uid | cut -f 1 -d " " > $EMU_PARAM_DIR/bf_uid_filelen
	add_fru "bf_uid" 15

	echo "mc_enable 0x30" >> $EMU_FILE_PATH
else
	#update the fru timer
	ipmb_update_timer_fru=$(echo "mc_add_fru_data 0x30 0 6 file 0 \"$EMU_PARAM_DIR/ipmb_update_timer\"")
	sed -i "s~.*ipmb_update_timer.*~$ipmb_update_timer_fru~" $EMU_FILE_PATH
fi

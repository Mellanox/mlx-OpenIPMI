#!/bin/sh

# To view whether this daemon failed to retrieve
# certain information needed by IPMI, use:
# journalctl -u set_emu_param

EMU_PARAM_DIR=/run/emu_param

if [ ! -d $EMU_PARAM_DIR ]; then
	mkdir $EMU_PARAM_DIR
fi

# BMC writes its ip address and the QSFP ports addresses to the
# BlueField through the ip_addresses files.
if [ ! -s  $EMU_PARAM_DIR/ip_addresses ]; then
	touch $EMU_PARAM_DIR/ip_addresses
	truncate -s 61 $EMU_PARAM_DIR/ip_addresses
fi

bffamily=$1
support_ipmb=$2
oob_ip=$3
external_ddr=$4
loop_period=$5
bf_version=$6

# This timer is used to update the FRUs
# once every hour. It also informs the user
# how much time is left before the next FRU
# update.
# This is needed in the case where customers
# need to retrieve FRU data 16 or 32 bytes at
# a time.
# set_emu_param.service executes set_emu_param.sh
# every $loop_period, so we need to execute this
# script $fru_timer times before an hour has
# passed and we can update the desired FRUs.
fru_timer=$((3600 / $loop_period))
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

# current time in seconds
curr_time=$((( $fru_timer - $t) * $loop_period ))

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
# ipmb_host driver is not installed in all images
IPMB_HOST_CLIENTADDR=0x10

BF2_PLATFORM_ID=0x00000214

if [ "$bffamily" = "Bluewhale" ]; then
	i2cbus=2
elif [ "$bffamily" = "BlueSphere" ] || [ "$bffamily" = "PRIS" ] ||
     [ "$bffamily" = "Camelantis" ] || [ "$bffamily" = "Aztlan" ] ||
     [ "$bffamily" = "Dell-Camelantis" ] || [ "$bffamily" = "Roy" ] ||
     [ "$bffamily" = "El-Dorado" ] || [ "$bffamily" = "Moonraker" ] ||
     [ "$bffamily" = "Goldeneye" ]; then
	i2cbus=1
else
	i2cbus=$support_ipmb
fi

I2C_NEW_DEV=/sys/bus/i2c/devices/i2c-$i2cbus/new_device
I2C_DEL_DEV=/sys/bus/i2c/devices/i2c-$i2cbus/delete_device
# The IPMB_HOST_FLAG is created if the ipmb-host driver is loaded by the BMC
# using ipmi oem command: ipmitool -I ipmb raw 0x2e 0x2 0x47 0x16 0x0
# This flag is cleared after reboot the DPU.
IPMB_HOST_FLAG=/run/emu_param/ipmb_host_driver_loaded
# The IPMB_RETRY_FLAG is created if the host driver is needed to be reloaded.
# This flag is cleared after reboot the DPU or successful retry.
IPMB_RETRY_FLAG=/run/emu_param/ipmb_host_driver_retry

load_ipmb_host() {
	# There is a corner case that the ipmb-host driver can be loaded by this
	# script and BMC at the same time. The handshake could be interrupted
	# and cause the driver panic.
	# If IPMB_HOST_FLAG exists on the system, that means the ipmb-host driver
	# is loaded by BMC and the BMC is ready to do the handshake with DPU, there
	# is no need to load it again. The script should check this flag before
	# loading the ipmb-host to avoid the ipmi-host is loading or loaded by the
	# BMC.
	if [ ! -f $IPMB_HOST_FLAG ]; then
		# The script should create this flag to avoid the BMC try to load the
		# driver when the script is loading it.
		touch $IPMB_HOST_FLAG
		modprobe ipmb_host slave_add=$IPMB_HOST_CLIENTADDR
		echo ipmb-host $IPMB_HOST_ADD > $I2C_NEW_DEV
		# The script should remove this flag to avoid the BMC can't reload the
		# driver after BMC boot up.
		rm $IPMB_HOST_FLAG
	fi
}

remove_ipmb_host() {
	if [ ! -f $IPMB_HOST_FLAG ]; then
		touch $IPMB_HOST_FLAG
		echo $IPMB_HOST_ADD > $I2C_DEL_DEV
		rmmod ipmb_host
		rm $IPMB_HOST_FLAG
	fi
}

if [ "$i2cbus" != "NONE" ]; then
	# Instantiate the ipmb-dev device
	if [ ! -c "/dev/ipmb-$i2cbus" ]; then
		echo ipmb-dev $IPMB_DEV_INT_ADD > $I2C_NEW_DEV
	fi

	if ! grep -q "ipmb-$i2cbus" /etc/ipmi/mlx-bf.lan.conf; then
		echo "  ipmb 2 ipmb_dev_int /dev/ipmb-$i2cbus" >> /etc/ipmi/mlx-bf.lan.conf
	fi
	if [ ! "$(lsmod | grep ipmi_msghandler)" ]; then
		modprobe ipmi_msghandler
	fi
	if [ ! "$(lsmod | grep ipmi_devintf)" ]; then
		modprobe ipmi_devintf
	fi
	
	# load the ipmb_host driver, if installed in BF
	is_ipmb_host_driver=false
	
    if find /lib/modules/ /usr/lib/modules/ \( -name "ipmb_host.ko" -o -name "ipmb-host.ko" \) -print -quit | grep -q .; then
		is_ipmb_host_driver=true
    fi
	# The BMC is slower than DPU to be ready on BF2 and BF1.
	# The BMC is faster than DPU to be ready on BF3.
	# Currently we want to keep the delay for BF2 and BF1.
	# As the bf_family name of Roy and Roy-B are the same for BF2 and BF3,
	# We need to check it is Roy or Roy-B according to the platform ID.
	# The bf_version is used to distinguish the "Roy" and "Roy-B".
	# Roy-B doesn't need the delay of loading the driver.
    if [ ! "$(lsmod | grep ipmb_host)" ] && $is_ipmb_host_driver; then
		if [ "$bffamily" = "BlueSphere" ] || [ "$bffamily" = "PRIS" ] ||
		   [ "$bffamily" = "Camelantis" ] || [ "$bffamily" = "Aztlan" ] ||
		   [ "$bffamily" = "Dell-Camelantis" ] || [ "$bffamily" = "El-Dorado" ] ||
		   ([ "$bffamily" = "Roy" ] && [ "$bf_version" = $BF2_PLATFORM_ID ]); then
			# Load the driver 2.5mn after boot to give the BMC time
			# to get ready for IPMB transactions.
			if [ "$curr_time" -ge 150 ]; then
				load_ipmb_host
				ipmitool mc info > /dev/null 2>&1
				if [ ! $? -eq 0 ]; then
					touch $IPMB_RETRY_FLAG
				fi
			fi
		else
			load_ipmb_host
			ipmitool mc info > /dev/null 2>&1
			if [ ! $? -eq 0 ]; then
				touch $IPMB_RETRY_FLAG
			fi
		fi
	fi
	# The i2c bus between BMC and DPU could be overused and susceptible to be busy.
	# Retry every 6mn after boot if the driver fails to load.
	if [ -f $IPMB_RETRY_FLAG ]; then
		if [ $(( $t % 6 )) -eq 0 ] && [ "$curr_time" -ge 300 ]; then
			remove_ipmb_host
			load_ipmb_host
			ipmitool mc info > /dev/null 2>&1
			if [ $? -eq 0 ]; then
				rm $IPMB_RETRY_FLAG
			fi
		fi
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

###################################################################################################
# Collect sensor and fru data                                                                     #
###################################################################################################

remove_sensor() {
	rm -f $EMU_PARAM_DIR/$1
}

grep_for_dimm_temp() {
	# In Yocto, grep for the "DDR4 Temp" string, since we use a customized sensors.conf file.
	# But in CentOS, libsensors is yum installed so grep for the default "temp1:" string.
	grep "DDR4 Temp:" $EMU_PARAM_DIR/$1_info > $EMU_PARAM_DIR/DDR4_str
	grep "temp1:" $EMU_PARAM_DIR/$1_info > $EMU_PARAM_DIR/temp1_str
	if [ -s $EMU_PARAM_DIR/DDR4_str ]; then
		cat $EMU_PARAM_DIR/DDR4_str | cut -d "+" -f 2 | cut -d "." -f 1 > $EMU_PARAM_DIR/$1
	elif [ -s $EMU_PARAM_DIR/temp1_str ]; then
		cat $EMU_PARAM_DIR/temp1_str | cut -d "+" -f 2 | cut -d "." -f 1 > $EMU_PARAM_DIR/$1
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
	mlxlink -d $1 --cable --read --page 0 --offset 0 --length 256 \
	| grep "page\[0\].Byte"  | cut -f 2 -d ":" | tr -d ' ' \
	| tr -d "\n"  | perl -lpe '$_=pack"H*",$_' >  $EMU_PARAM_DIR/tmp

	# Make sure binary data packed is 256 bytes
	dd if=$EMU_PARAM_DIR/tmp of=$EMU_PARAM_DIR/$2 bs=1 skip=0 count=256

	rm $EMU_PARAM_DIR/tmp
}

# $1 is the mst cable name
# $2 is the output file name
get_qsfp_temp() {
	temp=$(mlxlink -d $1 -m 2> /dev/null | grep Temperature | cut -f 2 -d ":" | tr -d " ")
	if [ "$temp" != "N/A" ]; then
		temp=$(echo "$temp" | awk -F'[^0-9]+' '{print $1}')
		echo $temp > $EMU_PARAM_DIR/$2
	else
		remove_sensor "$2"
	fi
}

# $1 is the full path of the ethernet or infiniband bdfs file
update_cables_info()
{
	if [ -s $1 ]; then
		while read bdf; do
			# Get number of link and the link status
			func=$(echo $bdf | cut -f 1 -d " " | cut -f 2 -d ".")
			# Parse link status from mlxlink
			link_status=$(mlxlink -d "$bdf" --cable --ddm | awk -F ":" '/State/{print $2}')
			# Update port link status
			case "$link_status" in 
				*Active*)
				echo 1 > $EMU_PARAM_DIR/p$func"_link"
				;;
				*LinkUp*)
				echo 1 > $EMU_PARAM_DIR/p$func"_link"
				;;
				*)
				echo 2 > $EMU_PARAM_DIR/p$func"_link"
				;;
			esac
			mlxlink -d $bdf --cable --ddm > /dev/null 2>&1
			# The port is connected
			if [ $? -eq 0 ]; then	
				### Get the temperature for QSFP the port ###
				get_qsfp_temp $bdf "p${func}_temp"
				### Update the qsfp eeprom fru
				get_qsfp_eeprom_data $bdf "qsfp${func}_eeprom"
			# The port is disconnect
			else
				remove_sensor "p${func}_temp"
				echo "QSFP${func} EEPROM not detected" > $EMU_PARAM_DIR/qsfp${func}_eeprom
				truncate -s 256 $EMU_PARAM_DIR/qsfp${func}_eeprom
			fi
		done < $1
	fi
}

# Getting Link Interface data using nmcli command.
get_port_data() {
    port_name="$1"
    file_index="$2"  
    file_name="$3"
    file_path="$EMU_PARAM_DIR/$file_name$file_index"

    # Fetch the device's connected/unmanaged status and prepare the message
    status_line=$(nmcli -t -f DEVICE,STATE device status | grep "$port_name")

    echo "$status_line" >> "$file_path"
}

##########################################################
# Get connectX network interfaces information            #
#                                                        #
# $1 is the port's index                                 #
# $2 is bool- true if board has both Eth port and IB port#
# $3 is the file name that will save port's information  #
##########################################################
get_connectx_net_info() {
	# In the BlueWhale and other similar designs,
	# udev renames the interfaces to enp*f* while on
	# the SNIC, the connectX interfaces are renamed p0 and p1
	# Make sure to parse out the VLAN interfaces as well. For ex: enp3s0f0np0.100
	# Using 'ip -s link' command for consistency between different OSes
	# When the board has 2 ports that one is IB and the other is ETH, IB port will have index '0'
	file_name="$3"
	get_port_info_cmd="ip -s link"
	if [ "$file_name" != "oob" ]; then
		# Looking for the port name in the output of the ip command
		eth=$($get_port_info_cmd | grep -o "enp.*f$1.*:" | head -1 | awk -F: '{print $1}')
		if [ -z "$eth" ]; then
			eth=$($get_port_info_cmd | grep -o "ib$1" | head -1)
			if [ -z "$eth" ]; then  
				eth=$($get_port_info_cmd | grep -o "p$1" | head -1)
				if $2 && [ -z "$eth" ]; then  
					eth="ib0"
				else
					eth="p$1"
				fi
			fi
		fi
	else
		# file name given is "oob"
		eth=$($get_port_info_cmd | grep -o "oob_net$1" | head -1)
	fi

	if [ "$file_name" != "oob" ]; then
		if [ "$1" = "0" ]; then
			echo "LAN interface: $eth" > $EMU_PARAM_DIR/eth_hw_counters
		else
			echo "LAN interface: $eth" >> $EMU_PARAM_DIR/eth_hw_counters
		fi
	fi

	if [ -d /sys/class/infiniband/mlx5_$1/ports/1/hw_counters ]; then
		cd /sys/class/infiniband/mlx5_$1/ports/1/hw_counters
		grep '' * >> $EMU_PARAM_DIR/eth_hw_counters
	fi

	echo "LAN Interface:" > $EMU_PARAM_DIR/$file_name$1
	ifconfig $eth >> $EMU_PARAM_DIR/$file_name$1 2>/dev/null
	# Getting output from both ifconfig and ip for compatibility with older BMC versions
	if ip link show dev $eth >> $EMU_PARAM_DIR/$file_name$1 2>/dev/null; then
		sed -i 's/^[0-9]*: //' $EMU_PARAM_DIR/$file_name$1
	else
		# if this interface is not supported, update FRU file NA
		echo "NA" > $EMU_PARAM_DIR/$file_name$1

		# Pad the file with spaces in case the size of the temp files increases
		truncate -s 3200 $EMU_PARAM_DIR/$file_name$1
		return
	fi
	get_port_data "$eth" "$1" "$file_name"
	ethtool $eth | grep -i "speed" >> $EMU_PARAM_DIR/$file_name$1

	# Get gateway
	ip r | grep default | grep "dev $eth" >> $EMU_PARAM_DIR/$file_name$1

	# Get the connection name
	connection_name=$(nmcli -g GENERAL.CONNECTION dev show $eth)

	# Check if IPv4 address is assigned and is not a link local address
	ifconfig $eth | grep "inet " | grep -v " 169.254."
	if [ $? -eq 0 ]; then

		# Check IPv4 connection type
		file=$(nmcli -g ipv4.method con show $connection_name)

		if [ "$file" = "auto" ]; then
			echo "IPv4 Address Origin: DHCP" >> $EMU_PARAM_DIR/$file_name$1
		elif [ "$file" = "manual" ]; then
			echo "IPv4 Address Origin: Static" >> $EMU_PARAM_DIR/$file_name$1
		else
			echo "IPv4 Address Origin: LinkLocal" >> $EMU_PARAM_DIR/$file_name$1
		fi
	else
		echo "IPv4 Address Origin: LinkLocal" >> $EMU_PARAM_DIR/$file_name$1
	fi

	# Check if IPv6 address is assigned and is not a link local address
	ifconfig $eth | grep "inet6 " | grep -v " fe80::"
	if [ $? -eq 0 ]; then

		# Check IPv6 connection type
		file=$(nmcli -g ipv6.method con show $connection_name)

		if [ "$file" = "auto" ]; then
			echo "IPv6 Address Origin: DHCP" >> $EMU_PARAM_DIR/$file_name$1
		elif [ "$file" = "manual" ]; then
			echo "IPv6 Address Origin: Static" >> $EMU_PARAM_DIR/$file_name$1
		else
			echo "IPv6 Address Origin: LinkLocal" >> $EMU_PARAM_DIR/$file_name$1
		fi
	else
		echo "IPv6 Address Origin: LinkLocal" >> $EMU_PARAM_DIR/$file_name$1
	fi

	data="prio|rx_symbol_err_phy|rx_pcs_symbol_err_phy|rx_crc_errors_phy"
	data+="|rx_corrected_bits_phy|[rt]x_pause_ctrl"
	ethtool -S $eth | grep -E $data >> $EMU_PARAM_DIR/$file_name$1
	echo "End LAN Interface" >> $EMU_PARAM_DIR/$file_name$1

	# Pad the file with spaces in case the size of the temp files increases
	truncate -s 3200 $EMU_PARAM_DIR/$file_name$1
}


####################################################
#               Get SPDs' information              #
####################################################
# The following addresses are all in hex.
SPD0_I2C_ADDR=50
SPD1_I2C_ADDR=51
SPD2_I2C_ADDR=52
SPD3_I2C_ADDR=53

SPDS_ADDR="$SPD0_I2C_ADDR $SPD1_I2C_ADDR $SPD2_I2C_ADDR $SPD3_I2C_ADDR"

I2C1_DEVPATH=/sys/bus/i2c/devices/i2c-1/new_device

if [ "$bffamily" = "Bluewhale" ] || [ "$external_ddr" = "YES" ]; then
	if [ ! "$(lsmod | grep ee1004)" ]; then
		modprobe ee1004
	fi
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

if [ ! -s $EMU_PARAM_DIR/ddr0_0_spd ] && [ -s /sys/bus/i2c/drivers/ee1004/1-0050/eeprom ]; then
	cp /sys/bus/i2c/drivers/ee1004/1-0050/eeprom $EMU_PARAM_DIR/ddr0_0_spd
else
	truncate -s 512 $EMU_PARAM_DIR/ddr0_0_spd
fi

if [ ! -s $EMU_PARAM_DIR/ddr0_1_spd ] && [ -s /sys/bus/i2c/drivers/ee1004/1-0051/eeprom ]; then
	cp /sys/bus/i2c/drivers/ee1004/1-0051/eeprom $EMU_PARAM_DIR/ddr0_1_spd
else
	truncate -s 512 $EMU_PARAM_DIR/ddr0_1_spd
fi

if [ ! -s $EMU_PARAM_DIR/ddr1_0_spd ] && [ -s /sys/bus/i2c/drivers/ee1004/1-0052/eeprom ]; then
	cp /sys/bus/i2c/drivers/ee1004/1-0052/eeprom $EMU_PARAM_DIR/ddr1_0_spd
else
	truncate -s 512 $EMU_PARAM_DIR/ddr1_0_spd
fi

if [ ! -s $EMU_PARAM_DIR/ddr1_1_spd ] && [ -s /sys/bus/i2c/drivers/ee1004/1-0053/eeprom ]; then
	cp /sys/bus/i2c/drivers/ee1004/1-0053/eeprom $EMU_PARAM_DIR/ddr1_1_spd
else
	truncate -s 512 $EMU_PARAM_DIR/ddr1_1_spd
fi

###############################################
#           Get DIMMs' temperature            #
###############################################
if [ "$bffamily" = "Bluewhale" ] || [ "$external_ddr" = "YES" ]; then
	if [ ! "$(lsmod | grep jc42)" ]; then
		modprobe jc42

		if [ "$(lsmod | grep jc42)" ]; then
			sensors -s
		fi
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
#  QSFP ports temperature and QSFP EEPROM data aka VPDs     #
#############################################################
# To get the NIC VID, SVID, DID and SDID, we use the pci dev
# info (lspci). The pci bus number is set by the OS and is
# likely to change if someone adds a card in the pci slot.
# So we use the pci device class number to determine the bdf
# for the NIC pci. The NIC card can be associated with device
# class 0200 if it is connected via pcie or class 0207 if it
# is connected via infiniband.
# If a port is not connected or if its temperature is reported as
# "N/A" by FW, then the ipmitool command will display "no reading".

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

	truncate -s 200 $EMU_PARAM_DIR/nic_pci_dev_info

	update_cables_info $EMU_PARAM_DIR/eth_bdfs.txt
	update_cables_info $EMU_PARAM_DIR/ib_bdfs.txt

fi
rm -f $EMU_PARAM_DIR/eth_bdfs.txt
rm -f $EMU_PARAM_DIR/ib_bdfs.txt

###################################
#          Get FW info            #
###################################
#
# /sys/class/infiniband/mlx* exists for both infiniband and ethernet.
# The reason for that is RoCE, which implements the infiniband protocol
# (RDMA), with ethernet as the link layer instead of IB.
#
get_fw_info() {
	cat <<- EOF > $EMU_PARAM_DIR/fw_info
	$(/usr/bin/bfver | sed '1d')
	BlueField OFED Version: $(ofed_info -s | sed 's/.$//')
	EOF

	# Get VPD info
	cat <<- EOF >> $EMU_PARAM_DIR/fw_info
	vpd info:
	$(mlxvpd -d /dev/mst/mt*_pciconf0)
	EOF

	if [ -d /sys/class/infiniband/mlx*_0 ]; then
		port=0
	elif [ -d /sys/class/infiniband/mlx*_1 ]; then
		port=1
	else
		port=-1
	fi

	if [ "$port" = "-1" ]; then
		cat <<- EOF >> $EMU_PARAM_DIR/fw_info
		Unable to get connectx fw info since the network ports are not configured.
		EOF
	else
		cat <<- EOF >> $EMU_PARAM_DIR/fw_info
		connectx_fw_ver: $(cat /sys/class/infiniband/mlx*_$port/fw_ver)
		board_id: $(cat /sys/class/infiniband/mlx*_$port/board_id)
		node_guid: $(cat /sys/class/infiniband/mlx*_$port/node_guid)
		sys_image_guid: $(cat /sys/class/infiniband/mlx*_$port/sys_image_guid)
		EOF
	fi

	if [ "$bffamily" = "BlueSphere" ]; then
		ssd_v=$(lspci -vv  | grep "Non-Volatile memory controller" | cut -d ":" -f 3)
		if [ -z "$ssd_v" ]; then
			ssd_v="No SSD found"
		fi
		echo "M.2 SSD version:$ssd_v" >> $EMU_PARAM_DIR/fw_info
	fi

	truncate -s 2000 $EMU_PARAM_DIR/fw_info
}

###################
# DIMMs CE and UE #
###################
# add trailing spaces to each line so that the dimms_ce_ue FRU can be updated
# when the number of errors increases.
if [ $(( $curr_time % 10 )) -eq 0 ]; then
  ras-mc-ctl --error-count > $EMU_PARAM_DIR/ce_ue_tmp
  { grep 'Label\|mc#0' $EMU_PARAM_DIR/ce_ue_tmp; grep -v 'Label\|mc#0' $EMU_PARAM_DIR/ce_ue_tmp; } > $EMU_PARAM_DIR/ce_ue_tmp1
  awk '{printf "%-100s\n", $0}' $EMU_PARAM_DIR/ce_ue_tmp1 > $EMU_PARAM_DIR/dimms_ce_ue
  truncate -s 303 $EMU_PARAM_DIR/dimms_ce_ue
fi


###################################
# Create ConnectX interfaces FRUs #
###################################
# Update eth0 and eth1 files every 60 seconds

if [ $(( $curr_time % 60 )) -eq 0 ]; then
# eth_and_ib will be true if board has a Eth configured port and a IB configured port
	eth_and_ib=false
	if lspci -n | grep 0200 | cut -f 1 -d " " | grep -q .
	then
		if lspci -n | grep 0207 | cut -f 1 -d " " | grep -q .
		then
			eth_and_ib=true
		fi
	fi
	# Get 100G network interfaces information
	get_connectx_net_info "0" $eth_and_ib "eth" # Data port in index 0
	get_connectx_net_info "1" $eth_and_ib "eth" # Data port in index 1 (if exists)
	get_connectx_net_info "0" false "oob"       # Out-Of-Band port in index 0
fi
truncate -s 3000 $EMU_PARAM_DIR/eth_hw_counters


###################################
#        Get the product name     #
###################################
update_product_name=false
if [ $update_product_name = false ]; then
	product_name=$(dmidecode | grep -i "Product Name" | cut -d':' -f2- | head -n 1)
	if [ -n "$product_name" ]; then
	  echo $product_name> $EMU_PARAM_DIR/product_name
	  truncate -s 64 $EMU_PARAM_DIR/product_name
	  update_product_name=true
	fi
fi

# We don't want to update the FRU data as often as the temp values
# or the link status for 2 reasons:
# - The FRUs are not really susceptible to change unless the user makes changes directly to HW
# - Some users need enough time to retrieve FRUs via ipmitool raw command.
# So only update it once every hour.
if [ "$t" = "$fru_timer" ]; then
	###################################
	#        Get the fru info         #
	###################################
	flint -d /dev/mst/mt*_pciconf0 q full > $EMU_PARAM_DIR/bf_fru
	truncate -s 1280 $EMU_PARAM_DIR/bf_fru

	###################################
	#        Get the fw info          #
	###################################
	get_fw_info


	###################################
	#        Get the cpu info         #
	###################################
	lscpu > $EMU_PARAM_DIR/cpuinfo
	cat /proc/cpuinfo >> $EMU_PARAM_DIR/cpuinfo
	truncate -s 6200 $EMU_PARAM_DIR/cpuinfo


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
	echo $CID |tr -d ' ' | tr -d '\n' | perl -lpe '$_=pack"H*",$_' > $EMU_PARAM_DIR/temp
	dd if=$EMU_PARAM_DIR/temp of=$EMU_PARAM_DIR/emmc_cid bs=1 skip=0 count=16

	# CSD binary data
	CSD=`find /sys/devices -name 'csd'| grep mmc| xargs cat| sed 's/.\{2\}/& /g'`
	if [ -z "$CSD" ]; then
		CSD=`printf '00 %.0s' $(seq 1 16)`
	fi
	echo $CSD |tr -d ' ' | tr -d '\n' | perl -lpe '$_=pack"H*",$_' > $EMU_PARAM_DIR/temp
	dd if=$EMU_PARAM_DIR/temp of=$EMU_PARAM_DIR/emmc_csd bs=1 skip=0 count=16

	# Ext CSD binary data
	EXTCSD=`cat '/sys/kernel/debug/mmc0/mmc0:0001/ext_csd' | sed 's/.\{2\}/& /g'`
	if [ -z "$EXTCSD" ]; then
		EXTCSD=`printf 'ff %.0s' $(seq 1 16)`
	fi
	echo $EXTCSD |tr -d ' ' | tr -d '\n' | perl -lpe '$_=pack"H*",$_' > $EMU_PARAM_DIR/temp
	dd if=$EMU_PARAM_DIR/temp of=$EMU_PARAM_DIR/emmc_extcsd bs=1 skip=0 count=512

	rm $EMU_PARAM_DIR/temp

	# Concatenate the binaries together
	cat $EMU_PARAM_DIR/emmc_cid $EMU_PARAM_DIR/emmc_csd $EMU_PARAM_DIR/emmc_extcsd >> $EMU_PARAM_DIR/emmc_info

	truncate -s 2000 $EMU_PARAM_DIR/emmc_info


	##########################################
	#          Get BF UID info               #
	##########################################
	mlxreg -d /dev/mst/mt*_pciconf0 --reg_name MDIR --get | awk '{if(NR>2)print}' \
	       	| grep device | cut -d "x" -f 2 | tr -d '\n' > $EMU_PARAM_DIR/bf_uid
	if [ ! -s $EMU_PARAM_DIR/bf_uid ]; then
		cat <<- EOF > $EMU_PARAM_DIR/bf_uid
		Failed to retrieve the BF UID. Please update to FW version xx.28.1068 or higher and
		to MFT version 4.15.0-104 or higher.
		EOF
	fi
fi

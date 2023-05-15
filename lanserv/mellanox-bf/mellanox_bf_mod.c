// SPDX-License-Identifier: GPL-2.0-only OR BSD-3-Clause

/* OEM handlers for Mellanox BlueField 
 *
 * Copyright (C) 2023 NVIDIA CORPORATION & AFFILIATES
 * 
 * This code is based on  Corey Minyard's /marvell-bmc/mervel_mod.c
 */
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <sys/time.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>

#include <OpenIPMI/ipmi_msgbits.h>
#include <OpenIPMI/ipmi_bits.h>
#include <OpenIPMI/serv.h>
#include <lanserv/OpenIPMI/mcserv.h>
#include <lanserv/bmc.h>

#define PVERSION "1.0.1"
#define IPMI_IANA_OEM_GET_SYSTEM_TIME_CMD	0x01

/**************************************************************************
 * Nvidia - Mellanox OEM commands.
 *************************************************************************/

/*
* Handler for getting the DPU system time (real time - UTC) 
*/
static void ipmi_get_system_time(lmc_data_t    *mc,
                                 msg_t         *msg,
                                 unsigned char *rdata,
                                 unsigned int  *rdata_len,
                                 void          *cb_data)
{
    sys_data_t *sys = cb_data;
    struct timeval t;

    mc->emu->sysinfo->get_real_time(mc->emu->sysinfo, &t);        
    rdata[0] = 0;
    ipmi_set_uint32(rdata+1, t.tv_sec);
    *rdata_len = 5;
}

int ipmi_sim_module_print_version(sys_data_t *sys, char *initstr)
{
    printf("IPMI Simulator Nvidia - Mellanox bf module version %s\n", PVERSION);
    return 0;
}

/**************************************************************************
 * Module initialization
 *************************************************************************/

int ipmi_sim_module_init(sys_data_t *sys, const char *initstr_i)
{
    int rv;

    rv = ipmi_emu_register_iana_handler(IPMI_IANA_OEM_GET_SYSTEM_TIME_CMD,
                ipmi_get_system_time, sys);
    if (rv) {
        sys->log(sys, OS_ERROR, NULL,
            "Unable to register Mellanox IANA handler: %s", strerror(rv));
    }

    return 0;
}

int ipmi_sim_module_post_init(sys_data_t *sys)
{
    return 0;
}
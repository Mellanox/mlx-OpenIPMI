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
#include <sys/syscall.h>
#include <linux/module.h>
#include <fcntl.h>
#include <ctype.h>

#include <OpenIPMI/ipmi_msgbits.h>
#include <OpenIPMI/ipmi_bits.h>
#include <OpenIPMI/serv.h>
#include <lanserv/OpenIPMI/mcserv.h>
#include <lanserv/bmc.h>

#define PVERSION             "1.0.2"
#define NVIDIA_IANA          5703
#define GET_SYSTEM_TIME_CMD  1
#define LOAD_IPMB_DRIVER_CMD 2

#define IPMB_HOST_PATH           "modinfo ipmb_host --field filename"
#define FLAG_PATH                "/run/emu_param/ipmb_host_driver_loaded"
#define IPMB_HOST_PARAM          "slave_add=0x10"
#define REGISTER_I2C_NEW_DEVICE  "echo ipmb-host 0x1011 > /sys/bus/i2c/devices/i2c-1/new_device"
#define I2C_NEW_DEVICE           "/sys/bus/i2c/devices/i2c-1/1-1011/"

#define init_module(module_image, len, param_values) syscall(__NR_init_module, module_image, len, param_values)
#define delete_module(name, flags) syscall(__NR_delete_module, name, flags)

/**************************************************************************
 * Nvidia - Mellanox OEM commands.
 *************************************************************************/

/**
 * Checks in /proc/modules whether a kernel module is loaded
 *
 * @param driver The name of the driver
 * @return 1 if the module is loaded, 0 otherwise
 */
static int module_is_loaded(char *driver)
{
    /* use the same buffer length as lsmod */
    char buffer[4096];
    FILE * fmod = fopen("/proc/modules", "r");
    int ret = 0;

    int mod_len = strlen(driver);
    if (mod_len > 4095) {
        return 0;
    }

    if (!fmod) {
        return 0;
    }

    while (fgets(buffer, sizeof(buffer), fmod)) {
        if (!strncmp(buffer, driver, mod_len) && isspace(buffer[mod_len])) {
            /* module is found */
            ret = 1;
            break;
        }
    }

    fclose(fmod);
    return ret;
}

/**
 * Load the ipmb_host driver
 *
 * @return 1 if the ipmb_host is loaded successful, 0 otherwise
 */
static int load_ipmb_host_driver()
{
    int ret = 0;
    int driver_fd, path_len;
    size_t module_size;
    struct stat st;
    void *module;
    char path_buffer[256];
    FILE * fp;

    /* ipmb_host is already loaded before the BMC booted up, need unload it first */
    if (module_is_loaded("ipmb_host") == 1) {
        if (delete_module("ipmb_host", O_NONBLOCK) != 0) {
            return ret;
        }
    }

    /* Read the path of ipmb_host driver file*/
    fp = popen(IPMB_HOST_PATH, "r");
    if (!fp) {
        return ret;
    }
    fgets(path_buffer, sizeof(path_buffer), fp);
    pclose(fp);
    path_len = strlen(path_buffer);
    path_buffer[path_len-1] = '\0';

    /* Start loading the driver */
    driver_fd = open(path_buffer, O_RDONLY);
    if (driver_fd < 0) {
        return ret;
    }
    fstat(driver_fd, &st);
    module_size = st.st_size;
    module = malloc(module_size);
    if(!module) {
        return ret;
    }
    read(driver_fd, module, module_size);
    close(driver_fd);
    if (init_module(module, module_size, IPMB_HOST_PARAM) != 0) {
        free(module);
        return ret;
    }
    free(module);

    /* Register the new I2C device if not exist*/
    if (access(I2C_NEW_DEVICE, F_OK) != 0) {
        if (system(REGISTER_I2C_NEW_DEVICE) == -1) {
            return ret;
        }
    }
    ret = 1;
    return ret;
}

/*
* Handler for getting the DPU system time (real time - UTC)
*/
static void handle_oem_command(lmc_data_t    *mc,
                                 msg_t         *msg,
                                 unsigned char *rdata,
                                 unsigned int  *rdata_len,
                                 void          *cb_data)
{
    sys_data_t *sys = cb_data;
    struct timeval t;
    int flag_fd;

    switch (msg->cmd) {
    case GET_SYSTEM_TIME_CMD:
    {
        rdata[0] = 0;
        mc->emu->sysinfo->get_real_time(mc->emu->sysinfo, &t);
        ipmi_set_uint32(rdata+1, t.tv_sec);
        *rdata_len = 5;
    }
    break;

    case LOAD_IPMB_DRIVER_CMD:
    {
        rdata[0] = 0x0;
        *rdata_len = 2;

        /* If flag exists, driver don't need to be reloaded again */
        if (access(FLAG_PATH, F_OK) == 0) {
            rdata[1] = 0x2;
            return;
        }

        /* Create a flag to indicate that the handler tried to load ipmb_host driver */
        flag_fd = open(FLAG_PATH, O_RDWR | O_CREAT, S_IRUSR | S_IRGRP | S_IROTH);
        if (flag_fd < 0) {
            rdata[1] = 0x0;
            return;
        }

        /* Load the ipmb_host driver */
        /* Return 1 if the driver is loaded successful, 0 otherwise */
        if (load_ipmb_host_driver() == 1) {
            rdata[1] = 0x1;
        } else {
            rdata[1] = 0x0;
        }
    }
    break;

    default:
        handle_invalid_cmd(mc, rdata, rdata_len);
    break;
    }

    return;
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

    rv = ipmi_emu_register_iana_handler(NVIDIA_IANA,
                handle_oem_command, sys);
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
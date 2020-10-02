OpenIPMI

Mellanox specific OpenIPMI repository.

The following are patched on top of opensource OpenIPMI-2.0.25:
1) Add support to the IPMB protocol and channel
2) Add mellanox-bf specific directory containing:
    - the service collecting sensors/FRUs data
    - the service running the ipmi_sim program
    - sdr.30 file
    - mlx-bf.lan.conf file
    - mlx-bf.emu file
    - prog.conf configuration file for enabling support to IPMB
3) debian folder for Ubuntu and debian builds
4) mlx-OpenIPMI.spec file for CentOS builds

Motivations behind creating a github repo instead of keeping a patch within BlueField's local repos:
1) Facilitate the build for various linux distributions
2) Facilitate sharing this code with customers
3) Avoid redundant use of a patch file


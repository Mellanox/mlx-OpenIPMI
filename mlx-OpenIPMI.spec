#
# Copyright (c) 2019 Mellanox Technologies. All rights reserved.
#
# This Software is licensed under one of the following licenses:
#
# 1) under the terms of the "Common Public License 1.0" a copy of which is
#    available from the Open Source Initiative, see
#    http://www.opensource.org/licenses/cpl.php.
#
# 2) under the terms of the "The BSD License" a copy of which is
#    available from the Open Source Initiative, see
#    http://www.opensource.org/licenses/bsd-license.php.
#
# 3) under the terms of the "GNU General Public License (GPL) Version 2" a
#    copy of which is available from the Open Source Initiative, see
#    http://www.opensource.org/licenses/gpl-license.php.
#
# Licensee has the right to choose one of the above licenses.
#
# Redistributions of source code must retain the above copyright
# notice and one of the license notices.
#
# Redistributions in binary form must reproduce both the above copyright
# notice, one of the license notices in the documentation
# and/or other materials provided with the distribution.
#
#

%{!?_name: %define _name mlx-OpenIPMI}
%{!?_version: %define _version 2.0.25}
%{!?_release: %define _release 3}

Summary: %{_name} - Library interface to IPMI
Name: %{_name}
Version: %{_version}
Release: %{_release}%{?_dist}
License: GPLv2
Url: http://www.mellanox.com
Group: System Environment/Base
Source: %{_name}-%{_version}.tar.gz
BuildRoot: %{?build_root:%{build_root}}%{!?build_root:/var/tmp/OFED}
Vendor: Mellanox Technologies
Requires: rasdaemon


%description
This package contains shared library implementation of IPMI and the
basic tools used with OpenIPMI. It supports Mellanox specific BlueField sensors
and FRUs as well as the IPMB protocol.


%prep
%setup -q


%build
autoreconf -fi
%configure --with-mellanox-bf
sed -i 's|^hardcode_libdir_flag_spec=.*|hardcode_libdir_flag_spec=""|g' libtool
sed -i 's|^runpath_var=LD_RUN_PATH|runpath_var=DIE_RPATH_DIE|g' libtool
make %{?_smp_mflags}


%install
%make_install


%files
%defattr(-,root,root,-)
/usr/bin/openipmi_eventd
/usr/bin/openipmicmd
/usr/bin/openipmish
/usr/bin/rmcp_ping
/usr/bin/sdrcomp
/usr/bin/solterm
/usr/include/OpenIPMI/*
/usr/share/man/man1/ipmi_sim.1.gz
/usr/share/man/man1/ipmi_ui.1.gz
/usr/share/man/man1/openipmi_eventd.1.gz
/usr/share/man/man1/openipmicmd.1.gz
/usr/share/man/man1/openipmish.1.gz
/usr/share/man/man1/rmcp_ping.1.gz
/usr/share/man/man1/solterm.1.gz
/usr/share/man/man5/ipmi_lan.5.gz
/usr/share/man/man5/ipmi_sim_cmd.5.gz
/usr/share/man/man7/ipmi_cmdlang.7.gz
/usr/share/man/man7/openipmi_conparms.7.gz
/usr/share/man/man8/ipmilan.8.gz
%{_bindir}/ipmi*
%{_bindir}/set_emu_param.sh
%{_bindir}/poll_set_emu_param.sh
%{_bindir}/mlx_ipmid_init.sh
/usr/lib64/libOpen*
/usr/lib64/libIPMI*
/usr/lib64/pkgconfig/OpenIPMI*
/etc/ipmi/*
/var/ipmi_sim/mellanox/sdr.30.main
/lib/systemd/system/set_emu_param.service
/lib/systemd/system/mlx_ipmid.service
/etc/logrotate.d/mlx_ipmid
/etc/logrotate.d/set_emu_param
/etc/rsyslog.d/mlx_ipmid.conf
/etc/rsyslog.d/set_emu_param.conf

%changelog
* Thu May 20 2021 Asmaa Mnebhi <asmaa@nvidia.com> - 2.0.25-3
- Update version number to 2.0.25-3

* Wed Jan 23 2019 Asmaa Mnebhi <asmaa@mellanox.com> - 2.0.25-0
- First mlx-OpenIPMI-2.0.25 package

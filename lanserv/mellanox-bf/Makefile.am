AM_CFLAGS = -I$(top_srcdir)/include -I$(top_srcdir)/lanserv
EXTRA_DIST = mlx-bf.lan.conf.in
CLEANFILES = mlx-bf.lan.conf

pkglib_LTLIBRARIES = mellanox_bf_mod.la

mellanox_bf_mod_la_SOURCES = mellanox_bf_mod.c
mellanox_bf_mod_la_LDFLAGS = -module

noinst_DATA = mlx-bf.lan.conf

#very dirty hack for supporting different pkglib paths depending on distro
mlx-bf.lan.conf: $(srcdir)/mlx-bf.lan.conf.in
	sed "s|@pkglib@|$(pkglibdir)|g" $(srcdir)/mlx-bf.lan.conf.in > $(srcdir)/mlx-bf.lan.conf

install-data-local:
	$(INSTALL) -m 755 -d "$(DESTDIR)$(localstatedir)/ipmi_sim/mellanox/"; \
	$(INSTALL) -m 755 -d "$(DESTDIR)$(sysconfdir)/ipmi/"; \
	$(INSTALL) -m 755 -d "$(DESTDIR)/lib/systemd/system/"; \
	$(INSTALL) -m 755 $(srcdir)/set_emu_param.sh "$(DESTDIR)$(bindir)/"; \
	$(INSTALL) -m 755 $(srcdir)/poll_set_emu_param.sh "$(DESTDIR)$(bindir)/"; \
	$(INSTALL) -m 755 $(srcdir)/mlx_ipmid_init.sh "$(DESTDIR)$(bindir)/"; \
	$(INSTALL) -m 755 $(srcdir)/mlx_emu_init.sh "$(DESTDIR)$(bindir)/"; \
	$(INSTALL) -m 644 $(srcdir)/set_emu_param.service "$(DESTDIR)/lib/systemd/system/"; \
	$(INSTALL) -m 644 $(srcdir)/sdr.30.main "$(DESTDIR)$(localstatedir)/ipmi_sim/mellanox/"; \
	$(INSTALL) -m 644 $(srcdir)/mlx-bf.lan.conf "$(DESTDIR)$(sysconfdir)/ipmi/"; \
	$(INSTALL) -m 644 $(srcdir)/mlx-bf-base.emu "$(DESTDIR)$(sysconfdir)/ipmi/"; \
	$(INSTALL) -m 644 $(srcdir)/mlx-bf1.emu "$(DESTDIR)$(sysconfdir)/ipmi/"; \
	$(INSTALL) -m 644 $(srcdir)/mlx-bf2.emu "$(DESTDIR)$(sysconfdir)/ipmi/"; \
	$(INSTALL) -m 644 $(srcdir)/mlx-bf3.emu "$(DESTDIR)$(sysconfdir)/ipmi/"; \
	$(INSTALL) -m 755 $(srcdir)/progconf "$(DESTDIR)$(sysconfdir)/ipmi/"; \
	$(INSTALL) -m 644 $(srcdir)/mlx_ipmid.service "$(DESTDIR)/lib/systemd/system/"; \
	$(INSTALL) -m 755 -d "$(DESTDIR)/run/log/"; \
	$(INSTALL) -m 755 -d "$(DESTDIR)$(sysconfdir)/logrotate.d/"; \
	$(INSTALL) -m 755 -d "$(DESTDIR)$(sysconfdir)/rsyslog.d/"; \
	$(INSTALL) -m 644 $(srcdir)/mlx_ipmid "$(DESTDIR)$(sysconfdir)/logrotate.d/mlx_ipmid"; \
	$(INSTALL) -m 644 $(srcdir)/set_emu_param "$(DESTDIR)$(sysconfdir)/logrotate.d/set_emu_param"; \
	$(INSTALL) -m 644 $(srcdir)/mlx_ipmid.conf "$(DESTDIR)$(sysconfdir)/rsyslog.d/mlx_ipmid.conf"; \
	$(INSTALL) -m 644 $(srcdir)/set_emu_param.conf "$(DESTDIR)$(sysconfdir)/rsyslog.d/set_emu_param.conf";

uninstall-local:
	-rm -f "$(DESTDIR)/lib/systemd/system/set_emu_param.service"
	-rm -f "$(DESTDIR)$(bindir)/set_emu_param.sh"
	-rm -f "$(DESTDIR)$(bindir)/poll_set_emu_param.sh"
	-rm -f "$(DESTDIR)$(bindir)/mlx_ipmid_init.sh"
	-rm -f "$(DESTDIR)$(bindir)/mlx_emu_init.sh"
	-rm -f "$(DESTDIR)$(localstatedir)/ipmi_sim/mellanox/sdr.30.main"
	-rm -f "$(DESTDIR)$(sysconfdir)/ipmi/mlx-bf.lan.conf"
	-rm -f "$(DESTDIR)$(sysconfdir)/ipmi/mlx-bf-base.emu"
	-rm -f "$(DESTDIR)$(sysconfdir)/ipmi/mlx-bf1.emu"
	-rm -f "$(DESTDIR)$(sysconfdir)/ipmi/mlx-bf2.emu"
	-rm -f "$(DESTDIR)$(sysconfdir)/ipmi/mlx-bf3.emu"
	-rm -f "$(DESTDIR)$(sysconfdir)/ipmi/progconf"
	-rm -f "$(DESTDIR)/lib/systemd/system/mlx_ipmid.service"
	-rm -f "$(DESTDIR)$(sysconfdir)/logrotate.d/mlx_ipmid"
	-rm -f "$(DESTDIR)$(sysconfdir)/logrotate.d/set_emu_param"
	-rm -f "$(DESTDIR)$(sysconfdir)/rsyslog.d/mlx_ipmid.conf"
	-rm -f "$(DESTDIR)$(sysconfdir)/rsyslog.d/set_emu_param.conf"
	-rmdir "$(DESTDIR)/run/log/" 2>/dev/null
	-rmdir "$(DESTDIR)$(sysconfdir)/ipmi" 2>/dev/null
	-rmdir "$(DESTDIR)$(localstatedir)/ipmi_sim/mellanox" 2>/dev/null
	-rmdir "$(DESTDIR)/lib/systemd/system" 2>/dev/null


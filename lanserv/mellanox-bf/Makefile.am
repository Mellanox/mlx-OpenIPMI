
install-data-local:
	$(INSTALL) -m 755 -d "$(DESTDIR)$(localstatedir)/ipmi_sim/mellanox/"; \
	$(INSTALL) -m 755 -d "$(DESTDIR)$(sysconfdir)/ipmi/"; \
	$(INSTALL) -m 755 -d "$(DESTDIR)/lib/systemd/system/"; \
	$(INSTALL) -m 755 $(srcdir)/set_emu_param_bf1.sh "$(DESTDIR)$(bindir)/"; \
	$(INSTALL) -m 755 $(srcdir)/set_emu_param_bf2.sh "$(DESTDIR)$(bindir)/"; \
	$(INSTALL) -m 755 $(srcdir)/oneshot_emu_param.sh "$(DESTDIR)$(bindir)/"; \
	$(INSTALL) -m 755 $(srcdir)/poll_set_emu_param.sh "$(DESTDIR)$(bindir)/"; \
	$(INSTALL) -m 644 $(srcdir)/oneshot_emu_param.service "$(DESTDIR)/lib/systemd/system/"; \
	$(INSTALL) -m 644 $(srcdir)/set_emu_param.service "$(DESTDIR)/lib/systemd/system/"; \
	$(INSTALL) -m 644 $(srcdir)/sdr.30.main.bf1 "$(DESTDIR)$(localstatedir)/ipmi_sim/mellanox/"; \
	$(INSTALL) -m 644 $(srcdir)/sdr.30.main.bf2 "$(DESTDIR)$(localstatedir)/ipmi_sim/mellanox/"; \
	$(INSTALL) -m 644 $(srcdir)/mlx-bf.lan.conf "$(DESTDIR)$(sysconfdir)/ipmi/"; \
	$(INSTALL) -m 644 $(srcdir)/mlx-bf1.emu "$(DESTDIR)$(sysconfdir)/ipmi/"; \
	$(INSTALL) -m 644 $(srcdir)/mlx-bf2.emu "$(DESTDIR)$(sysconfdir)/ipmi/"; \
	$(INSTALL) -m 755 $(srcdir)/progconf "$(DESTDIR)$(sysconfdir)/ipmi/"; \
	$(INSTALL) -m 644 $(srcdir)/mlx_ipmid.service "$(DESTDIR)/lib/systemd/system/";

uninstall-local:
	-rm -f "$(DESTDIR)/lib/systemd/system/oneshot_emu_param.service"
	-rm -f "$(DESTDIR)/lib/systemd/system/set_emu_param.service"
	-rm -f "$(DESTDIR)$(bindir)/set_emu_param_bf1.sh"
	-rm -f "$(DESTDIR)$(bindir)/set_emu_param_bf2.sh"
	-rm -f "$(DESTDIR)$(bindir)/oneshot_emu_param.sh"
	-rm -f "$(DESTDIR)$(bindir)/poll_set_emu_param.sh"
	-rm -f "$(DESTDIR)$(localstatedir)/ipmi_sim/mellanox/sdr.30.main.bf1"
	-rm -f "$(DESTDIR)$(localstatedir)/ipmi_sim/mellanox/sdr.30.main.bf2"
	-rm -f "$(DESTDIR)$(sysconfdir)/ipmi/mlx-bf.lan.conf"
	-rm -f "$(DESTDIR)$(sysconfdir)/ipmi/mlx-bf1.emu"
	-rm -f "$(DESTDIR)$(sysconfdir)/ipmi/mlx-bf2.emu"
	-rm -f "$(DESTDIR)$(sysconfdir)/ipmi/progconf"
	-rm -f "$(DESTDIR)/lib/systemd/system/mlx_ipmid.service"
	-rmdir "$(DESTDIR)$(sysconfdir)/ipmi" 2>/dev/null
	-rmdir "$(DESTDIR)$(localstatedir)/ipmi_sim/mellanox" 2>/dev/null
	-rmdir "$(DESTDIR)/lib/systemd/system" 2>/dev/null


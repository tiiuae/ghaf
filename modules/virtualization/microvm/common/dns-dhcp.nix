# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
_: let
  domain = "ghaf";
in {
  # Disable resolved since we are using dnsmasq
  # This options defaults to false but has been
  # tested not to work with dnsmasq if not set
  # explicitly to false
  services.resolved.enable = false;
  # do not really use resolvconf for anything
  networking.resolvconf.enable = false;

  # dnsmasq prioritises /etc/hosts to which NixOS
  # generates hostname entry. Here we generate
  # additional hosts that is used to replace
  # /etc/hosts
  environment.etc."additional-hosts" = {
    text = ''
      127.0.0.1 localhost
      192.168.100.1 net-vm
    '';
    mode = "0444";
  };

  # Dnsmasq is used as a DHCP/DNS server inside the NetVM
  services.dnsmasq = {
    enable = true;
    settings = {
      # keep local queries within domain by
      # caching them within dnsmasq. query outside
      # only if name is not available locally
      local = ["/{domain}/192.168.100.1"];
      server = ["8.8.8.8"];
      dhcp-range = ["192.168.100.2,192.168.100.254"];
      dhcp-sequential-ip = true;
      dhcp-authoritative = true;
      domain = "${domain}";
      listen-address = ["127.0.0.1,192.168.100.1"];
      dhcp-option = [
        "option:router,192.168.100.1"
        "option:dns-server,192.168.100.1"
      ];
      expand-hosts = true;

      # see comment above with additional-hosts generation
      no-hosts = true;
      addn-hosts = "/etc/additional-hosts";

      domain-needed = true;
      bogus-priv = true;

      # local host names and static IP addresses
      dhcp-host = [
        "02:00:00:01:01:01,192.168.100.1,net-vm"
        "02:00:00:02:02:02,192.168.100.3,gui-vm"
      ];
    };
  };
}

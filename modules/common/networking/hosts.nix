# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{lib, ...}: {
  environment.etc.hosts = lib.mkForce {
    # please note that .100. network is not
    # reachable from ghaf-host. It's only reachable
    # guest-to-guest. Use to .101. (debug) to access
    # guests from host (no names)
    text = ''
      127.0.0.1 localhost
      192.168.100.1 net-vm
      192.168.100.2 log-vm
      192.168.100.3 gala-vm
      192.168.100.4 chromium-vm
      192.168.100.5 zathura-vm
      192.168.100.6 element-vm
      192.168.100.7 gui-vm
    '';
    mode = "0444";
  };
}

# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
{
  # Enable ssh hardening optionally only when development profile
  # is in use. This separate hardening module enables external
  # networks facing debug SSH access hardening
  config = lib.mkIf config.ghaf.profiles.debug.enable {
    services.openssh = {
      settings = {
        PasswordAuthentication = false;
        Ciphers = [
          "aes256-gcm@openssh.com"
          "aes128-gcm@openssh.com"
          "aes256-ctr"
          "aes192-ctr"
          "aes128-ctr"
        ];
      };
      # allow password auth in debug mode
      # from ghaf via internal network only
      extraConfig = ''
      Match Address !192.168.101.0/24
            PasswordAuthentication no
      Match Address 192.168.101.0/24
            PasswordAuthentication yes
      '';
    };
  };
}

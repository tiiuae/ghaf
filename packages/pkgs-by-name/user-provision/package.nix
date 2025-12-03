# SPDX-FileCopyrightText: 2025-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  adcli,
  brightnessctl,
  coreutils,
  dig,
  fido2-manage,
  gawk,
  gnugrep,
  gum,
  hostname,
  iputils,
  iproute2,
  jq,
  krb5,
  lib,
  netcat,
  ncurses,
  networkmanager,
  mount,
  oddjob,
  openldap,
  sssd,
  systemd,
  umount,
  writeShellApplication,
}:
writeShellApplication {
  name = "user-provision";
  runtimeInputs = [
    adcli
    brightnessctl
    coreutils
    dig
    fido2-manage
    gawk
    gnugrep
    gum
    hostname
    iputils
    iproute2
    jq
    krb5
    ncurses
    netcat
    networkmanager
    mount
    oddjob
    openldap
    sssd
    systemd
    umount
  ];
  text = builtins.readFile ./user-provision.sh;
  meta = {
    description = "Ghaf user provisioning script.";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
    license = lib.licenses.asl20;
  };
}

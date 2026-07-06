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
  iproute2,
  iputils,
  jq,
  krb5,
  lib,
  mount,
  ncurses,
  netcat,
  networkmanager,
  oddjob,
  openldap,
  qrencode,
  sssd,
  systemd,
  umount,
  writeShellApplication,
}:
writeShellApplication {
  name = "user-provision";
  runtimeInputs = [
    # keep-sorted start
    adcli
    brightnessctl
    coreutils
    dig
    fido2-manage
    gawk
    gnugrep
    gum
    hostname
    iproute2
    iputils
    jq
    krb5
    mount
    ncurses
    netcat
    networkmanager
    oddjob
    openldap
    qrencode
    sssd
    systemd
    umount
    # keep-sorted end
  ];
  text = builtins.readFile ../../../lib/gum-lib.sh + builtins.readFile ./user-provision.sh;
  meta = {
    description = "Ghaf user provisioning script.";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
    license = lib.licenses.asl20;
  };
}

# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# TODO: Please add by strict alphabetical order
#
{
  services = {
    NetworkManager-Dispatcher.serviceConfig = import ./NetworkManager-dispatcher.nix;
    alloy.serviceConfig = import ./alloy.nix;
    bluetooth.serviceConfig = import ./bluetooth.nix;
    dbus.serviceConfig = import ./dbus.nix;
    dnsmasq.serviceConfig = import ./dnsmasq.nix;
    enable-ksm.serviceConfig = import ./enable-ksm.nix;
    firewall.serviceConfig = import ./firewall.nix;
    generate-shutdown-ramfs.serviceConfig = import ./generate-shutdown-ramfs.nix;
    ghaf-session.serviceConfig = import ./ghaf-session.nix;
    greetd.serviceConfig = import ./greetd.nix;
    install-microvm-netvm.serviceConfig = import ./install-microvm-netvm.nix;
    kmod-static-nodes.serviceConfig = import ./kmod-static-nodes.nix;
    logrotate.serviceConfig = import ./logrotate.nix;
    logrotate-checkconf.serviceConfig = import ./logrotate-checkconf.nix;
    "microvm-tap-interfaces@".serviceConfig = import ./microvm-tap-interfaces.nix;
    "microvm-virtiofsd@".serviceConfig = import ./microvm-virtiofsd.nix;
    "microvm@".serviceConfig = import ./microvm.nix;
    nscd.serviceConfig = import ./nscd.nix;
    rtkit-daemon.serviceConfig = import ./rtkit-daemon.nix;
    seatd.serviceConfig = import ./seatd.nix;
    systemd-journal-catalog-update.serviceConfig = import ./systemd-journal-catalog-update.nix;
    systemd-journal-flush.serviceConfig = import ./systemd-journal-flush.nix;
    systemd-networkd-wait-online.serviceConfig = import ./systemd-networkd-wait-online.nix;
    systemd-random-seed.serviceConfig = import ./systemd-random-seed.nix;
    systemd-remount-fs.serviceConfig = import ./systemd-remount-fs.nix;
    systemd-rfkill.serviceConfig = import ./systemd-rfkill.nix;
    systemd-tmpfiles-clean.serviceConfig = import ./systemd-tmpfiles-clean.nix;
    systemd-tmpfiles-setup.serviceConfig = import ./systemd-tmpfiles-setup.nix;
    systemd-tmpfiles-setup-dev.serviceConfig = import ./systemd-tmpfiles-setup-dev.nix;
    systemd-udevd.serviceConfig = import ./systemd-udevd.nix;
    systemd-udev-trigger.serviceConfig = import ./systemd-udev-trigger.nix;
    systemd-user-sessions.serviceConfig = import ./systemd-user-sessions.nix;
    "user-runtime-dir@".serviceConfig = import ./user-runtime-dir.nix;
    vsockproxy.serviceConfig = import ./vsockproxy.nix;
    nw-packet-forwarder.serviceConfig = import ./nw-packet-forwarder.nix;
    # TODO: These were previously in release need more testing to turn on
    # NetworkManager.serviceConfig = import ./NetworkManager.nix;
    # audit.serviceConfig = import ./audit.nix;
    # sshd.serviceConfig = import ./sshd.nix;
    # "user@".serviceConfig = import ./user.nix;

    # Disabled services
    # pulseaudio.serviceConfig = import ./pulseaudio.nix;
    # systemd-fsck-root.serviceConfig = import ./systemd-fsck-root.nix;
    # network-local-commands.serviceConfig = import ./network-local-commands.nix;
  };
}

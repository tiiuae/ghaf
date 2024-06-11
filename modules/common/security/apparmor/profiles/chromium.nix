# Copyright 2024-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.ghaf.security.apparmor;
  xprofile =
    if config.ghaf.security.system-security.enable
    then ''
        capability sys_admin,
        capability sys_chroot,

        capability chown,
        capability fsetid,
        capability setgid,
        capability setuid,
        capability dac_override,
        capability sys_chroot,

        capability sys_ptrace,
        ptrace (read, readby),
        capability sys_chroot,
        capability ipc_lock,

        capability setuid,
        capability setgid,

        owner @{PROC}/[0-9]*/gid_map                                   w,
        owner @{PROC}/[0-9]*/setgroups                                 w,
        owner @{PROC}/[0-9]*/uid_map                                   w,
      }
    ''
    else ''
      }
    '';
in {
  ## Option to enable Apparmor profile for chromium
  options.ghaf.security.apparmor.apps.chromium = {
    enable = lib.mkOption {
      description = ''
        Enable Chromium AppArmor profile.
      '';
      type = lib.types.bool;
      default = false;
    };
  };
  ## Apparmor profile for Chromium
  config.security.apparmor.policies."bin.chromium" = lib.mkIf cfg.apps.chromium.enable {
    profile =
      ''
        abi <abi/3.0>,
        include <tunables/global>

        @{CHROMIUM} = ${pkgs.chromium.browser}/libexec/chromium/chromium
        @{INTEGER}=[0-9]{[0-9],}{[0-9],}{[0-9],}{[0-9],}{[0-9],}{[0-9],}{[0-9],}{[0-9],}{[0-9],}
        @{ETC}=/etc
        @{NIX_STORE}=/nix/store

        profile chromium  @{CHROMIUM} flags=(enforce){
           include <abstractions/base>
           include <abstractions/audio>
           include <abstractions/cups-client>
           include <abstractions/dbus-session>
           include <abstractions/gnome>
           include <abstractions/ibus>
           include <abstractions/kde>
           include <abstractions/nameservice>

           include "${pkgs.apparmorRulesFromClosure {name = "chromium";} [pkgs.chromium]}"

           ${config.environment.etc."os-release".source}                   r,
           ${config.environment.etc."lsb-release".source}                  r,

           # All of these are for sanely dropping from root and chrooting

           # optional
           capability sys_resource,
           owner @{PROC}/[0-9]*/gid_map                                    w,
           owner @{PROC}/[0-9]*/setgroups                                  w,
           owner @{PROC}/[0-9]*/uid_map                                    w,

           @{ETC}/nixos/**                                                 r,
           @{ETC}/nix/**                                                   r,
           @{NIX_STORE}/**                                                 mrix,

           @{sys}/kernel/mm/transparent_hugepage/hpage_pmd_size            r,
           @{sys}/devices/system/cpu/present                               r,
           @{sys}/devices/system/cpu/kernel_max                            r,
           @{sys}/devices/system/cpu/cpu[0-9]/cache/index[0-9]/size        r,
           @{sys}/bus/                                                     r,
           @{sys}/bus/**                                                   r,

           @{sys}/class/                                                   r,
           @{sys}/class/**                                                 r,
           @{sys}/devices/pci*/**                                          rw,
           @{sys}/devices/virtual/tty/**                                   r,
           @{sys}/devices/virtual/dmi/**                                   r,

           /tmp/.X[0-9]*-lock                                              r,

           @{CHROMIUM}                                                     mrix,
           ${pkgs.chromium}/share/{,**}                                    r,
           ${pkgs.chromium.sandbox}/bin/*                                  rix,
           ${pkgs.chromium.browser}  r,
           ${pkgs.chromium.browser}/share/{,**}                            r,
           ${pkgs.chromium.browser}/libexec/chromium/chromium              rix,
           ${pkgs.chromium.browser}/libexec/chromium/*.so                  mr,
           ${pkgs.chromium.browser}/libexec/chromium/*                     rix,
           ${pkgs.chromium.browser}/libexec/chromium/**                    r,

                 @{PROC}                                                   r,
                 @{PROC}/[0-9]*/net/ipv6_route                             r,
                 @{PROC}/[0-9]*/net/arp                                    r,
                 @{PROC}/[0-9]*/net/if_inet6                               r,
                 @{PROC}/[0-9]*/net/route                                  r,
                 @{PROC}/[0-9]*/net/ipv6_route                             r,
                 @{PROC}/[0-9]*/stat                                       rix,
                 @{PROC}/[0-9]*/task/@{tid}/comm                           rw,
                 @{PROC}/[0-9]*/task/@{tid}/status                         rix,
           owner @{PROC}/[0-9]*/cgroup                                     r,
           owner @{PROC}/[0-9]*/fd/                                        r,
           owner @{PROC}/[0-9]*/io                                         r,
           owner @{PROC}/[0-9]*/mountinfo                                  r,
           owner @{PROC}/[0-9]*/mounts                                     r,
           owner @{PROC}/[0-9]*/oom_score_adj                              w,
           owner @{PROC}/[0-9]*/smaps                                      rix,
           owner @{PROC}/[0-9]*/statm                                      rix,
           owner @{PROC}/[0-9]*/task/                                      r,
           owner @{PROC}/[0-9]*/cmdline                                    rix,
           owner @{PROC}/[0-9]*/environ                                    rix,
           owner @{PROC}/[0-9]*/clear_refs                                 rw,
           owner @{PROC}/self/*                                            r,
           owner @{PROC}/self/fd/*                                         rw,
                 @{PROC}/sys/kernel/yama/ptrace_scope                      rw,
                 @{PROC}/sys/fs/inotify/max_user_watches                   r,
                 @{PROC}/ati/major                                         r,

                 /dev/fb0                                                  rw,
                 /dev/                                                     r,
                 /dev/hidraw@{INTEGER}                                     rw,
                 /dev/shm/**                                               rw,
                 /dev/tty                                                  rw,
                 /dev/video@{INTEGER}                                      rw,
           owner /dev/shm/pulse-shm*                                       m,
           owner /dev/tty@{INTEGER}                                        rw,

           owner @{HOME}                                                   r,
           owner @{HOME}/.cache/chromium                                   wrk,
           owner @{HOME}/.cache/mesa_shader_cache/index                    wrk,
           owner @{HOME}/.cache/chromium/**                                mrwk,
           owner @{HOME}/.cache/fontconfig/**                              rwk,
           owner @{HOME}/.config/chromium                                  rwkm,
           owner @{HOME}/.config/chromium/**                               rwkm,
           owner @{HOME}/.config/**                                        rw,
           owner @{HOME}/.local/share/mime/mime.cache                      m,
           owner @{HOME}/.pki/nssdb/                                       rwk,
           owner @{HOME}/.pki/nssdb/**                                     rwk,
           owner @{HOME}/Downloads/                                        r,
           owner @{HOME}/Downloads/*                                       rw,
           owner @{run}/user/1000/                                         rw,
           owner @{run}/user/1000/**                                       rw,
           owner /tmp/**                                                   rwk,
           owner /var/tmp/**                                               m,

           owner /tmp/chromiumargs.?????? rw,

           deny /boot/EFI/systemd/**                                       r,
           deny /boot/EFI/nixos/**                                         r,
           deny /boot/loader/**                                            r,
           deny /.suspended                                                r,
           deny /boot/vmlinuz*                                             r,
           deny /var/cache/fontconfig/                                     w,

           ### Networking ###
           network inet stream,
           network inet6 stream,
           network inet dgram,
           #network inet6 dgrap,
           network netlink raw,
      ''
      + xprofile;
  };
}

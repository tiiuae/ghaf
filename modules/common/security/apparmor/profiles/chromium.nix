# Copyright 2024-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
{
  ## Apparmor profile for Chromium
  config.security.apparmor.policies."bin.chromium" = lib.mkIf config.ghaf.security.apparmor.enable {
    profile = ''
      abi <abi/3.0>,
      include <tunables/global>

      @{CHROMIUM} = ${pkgs.chromium}/bin/chromium
      @{INTEGER}=[0-9]{[0-9],}{[0-9],}{[0-9],}{[0-9],}{[0-9],}{[0-9],}{[0-9],}{[0-9],}{[0-9],}
      @{ETC}=/etc
      @{NIX_STORE}=/nix/store

      profile chromium  @{CHROMIUM} flags=(enforce){
        include <abstractions/base>
        include <abstractions/dbus-session>
        include <abstractions/fonts>
        include <abstractions/ibus>

        ${config.environment.etc."os-release".source}                   r,
        ${config.environment.etc."lsb-release".source}                  r,

        capability sys_admin,
        capability sys_chroot,
        capability sys_ptrace,

        ## include "${pkgs.apparmorRulesFromClosure { name = "chromium"; } [ pkgs.chromium ]}"

        deny @{ETC}/nixos/**                                            r,
        deny @{ETC}/nix/**                                              r,
        /nix/store/**                                                   mr,

        ptrace (read, readby),

        ${pkgs.xdg-utils}/bin/*                                         Cxr,
        ${pkgs.coreutils}/bin/*                                         ixr,
        ${pkgs.coreutils-full}/bin/*                                    ixr,
        ${pkgs.procps}/bin/ps                                           Uxr,
        ${pkgs.gnugrep}/bin/grep                                        ixr,
        ${pkgs.gnused}/bin/sed                                          ixr,
        ${pkgs.which}/bin/which                                         ixr,
        ${pkgs.gawk}/bin/awk                                            ixr,
        ${pkgs.chromium}/bin/*                                          ixr,
        ${pkgs.chromium.browser}/libexec/chromium/*                     ixr,
        ${pkgs.chromium}-sandbox/bin/*                                  ixr,


        @{sys}/kernel/mm/transparent_hugepage/hpage_pmd_size            r,
        @{sys}/devices/system/cpu/present                               r,
        @{sys}/devices/system/cpu/kernel_max                            r,
        @{sys}/devices/system/cpu/cpu[0-9]/cache/index[0-9]/size        r,
        @{sys}/bus/**                                                   r,
        @{sys}/class/                                                   r,
        @{sys}/class/**                                                 r,
        @{sys}/devices/pci*/**                                          rw,
        @{sys}/devices/virtual/tty/**                                   r,
        @{sys}/devices/virtual/dmi/**                                   r,

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
        owner @{PROC}/[0-9]*/gid_map                                    w,
        owner @{PROC}/[0-9]*/setgroups                                  w,
        owner @{PROC}/[0-9]*/uid_map                                    w,
        owner @{PROC}/[0-9]*/smaps                                      rix,
        owner @{PROC}/[0-9]*/statm                                      rix,
        owner @{PROC}/[0-9]*/task/                                      r,
        owner @{PROC}/[0-9]*/cmdline                                    rix,
        owner @{PROC}/[0-9]*/environ                                    rix,
        owner @{PROC}/[0-9]*/clear_refs                                 rw,
        owner @{PROC}/self/*                                            r,
        owner @{PROC}/self/exe                                          rix,
        owner @{PROC}/self/fd/*                                         rw,
              @{PROC}/sys/kernel/yama/ptrace_scope                      rw,
              @{PROC}/sys/fs/inotify/max_user_watches                   r,
              @{PROC}/ati/major                                         r,

              /dev/                                                     r,
              /dev/fb0                                                  rw,
              /dev/hidraw@{INTEGER}                                     rw,
              /dev/shm/**                                               rw,
              /dev/tty                                                  rw,
              /dev/video@{INTEGER}                                      rw,
        owner /dev/shm/pulse-shm*                                       m,
        owner /dev/tty@{INTEGER}                                        rw,
              /dev/v4l/**                                               rw,
              /dev/snd/**                                               rw,
              /dev/null                                                 rw,

        owner @{HOME}                                                   r,
        owner @{HOME}/.DCOPserver_*                                     r,
        owner @{HOME}/.ICEauthority                                     r,
        owner @{HOME}/.fonts.*                                          lrw,
        owner @{HOME}/.cache/                                           wrk,
        owner @{HOME}/.cache/**                                         wrk,
        owner @{HOME}/.config/chromium                                  rwkm,
        owner @{HOME}/.config/chromium/**                               rwkm,
        owner @{HOME}/.config/**                                        rw,
        owner @{HOME}/.local/**                                         rw,
        owner @{HOME}/.local/share/mime/mime.cache                      m,
        owner @{HOME}/.pki/nssdb/                                       rwk,
        owner @{HOME}/.pki/nssdb/**                                     rwk,
        owner @{HOME}/Downloads/                                        r,
        owner @{HOME}/Downloads/*                                       rw,

        owner @{HOME}/tmp/**                                            rwkl,
        owner @{HOME}/tmp/                                              rw,

        owner @{run}/user/[0-9]*/                                       rw,
        owner @{run}/user/[0-9]*/**                                     rw,

        # global tmp directories
        owner /var/tmp/**                                               rwkl,
        /var/tmp/                                                       rw,
        owner /tmp/**                                                   rwkl,
        /tmp/                                                           rw,
        /tmp/.X[0-9]*-lock                                              r,

        owner /tmp/chromiumargs.??????                                  rw,

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
      }
    '';
  };
}

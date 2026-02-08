# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
{
  _file = ./google-chrome.nix;

  ## Apparmor profile for Chromium
  config.security.apparmor.policies."bin.chrome" = lib.mkIf config.ghaf.security.apparmor.enable {
    state = "enforce";
    profile = ''
      abi <abi/3.0>,
      include <tunables/global>

      @{INTEGER}=[0-9]{[0-9],}{[0-9],}{[0-9],}{[0-9],}{[0-9],}{[0-9],}{[0-9],}{[0-9],}{[0-9],}
      @{ETC}=/etc
      @{NIX}=/nix
      @{RUN}=/run

      ${pkgs.google-chrome}/share/google/chrome/google-chrome {
        include <abstractions/base>
        include <abstractions/dbus-session>
        include <abstractions/fonts>
        include <abstractions/ibus>

        ${config.environment.etc."os-release".source}                   r,
        ${config.environment.etc."lsb-release".source}                  r,

        capability sys_admin,
        capability sys_chroot,
        capability sys_ptrace,

        deny @{ETC}/nixos/**                                            r,
        deny @{ETC}@{NIX}/**                                            r,
        @{NIX}/store/                                                   mr,
        @{NIX}/store/**                                                 mr,

        ptrace (read, readby),

        ${pkgs.dbus}/bin/dbus-send                                      ixr,
        ${pkgs.xdg-utils}/bin/*                                         ixr,
        ${pkgs.coreutils}/bin/*                                         ixr,
        ${pkgs.coreutils-full}/bin/*                                    ixr,
        ${pkgs.procps}/bin/ps                                           ixr,
        ${pkgs.gnugrep}/bin/grep                                        ixr,
        ${pkgs.gnused}/bin/sed                                          ixr,
        ${pkgs.which}/bin/which                                         ixr,
        ${pkgs.gawk}/bin/*                                              ixr,
        ${pkgs.google-chrome}/bin/*                                     ixr,
        ${pkgs.google-chrome}/share/google/chrome/*                     ixr,
        ${pkgs.chromium}-sandbox/bin/*                                  ixr,
        ${pkgs.givc-cli}/bin/givc-cli                                   ixr,
        ${pkgs.chrome-extensions.open-normal}/*                         ixr,
        ${config.ghaf.xdgitems.handlerPath}/bin/*                       ixr,
        /run/xdg/pdf/*                                                  rw,
        /run/xdg/image/*                                                rw,
        ${pkgs.systemd}/bin/*                                           ixr,
        ${pkgs.bashInteractive}/bin/*                                   ixr,
        ${pkgs.libressl.nc}/bin/*                                       ixr,
        ${pkgs.openssh}/bin/*                                           ixr,
        ${pkgs.perlPackages.FileMimeInfo}/bin/mimetype                  ixr,

        @{sys}/kernel/mm/transparent_hugepage/hpage_pmd_size            r,
        @{sys}/module/                                                  r,
        @{sys}/module/**                                                r,
        @{sys}/bus/                                                     r,
        @{sys}/bus/**                                                   r,
        @{sys}/class/                                                   r,
        @{sys}/class/**                                                 r,
        @{sys}/devices/                                                 r,
        @{sys}/devices/**                                               r,
        @{sys}/fs/                                                      r,
        @{sys}/fs/**                                                    r,
        @{sys}/dev/                                                     rw,
        @{sys}/dev/**                                                   rw,
        @{sys}/devices/pci*/**                                          rw,

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
        owner @{PROC}/[0-9]*/comm                                       rw,
        owner @{PROC}/[0-9]*/statm                                      r,
        owner @{PROC}/[0-9]*/smaps_rollup                               r,
        owner @{PROC}/self/**                                           r,
        owner @{PROC}/self/exe                                          rix,
        owner @{PROC}/self/fd/*                                         rwkm,
              @{PROC}/sys/kernel/yama/ptrace_scope                      rw,
              @{PROC}/sys/fs/inotify/max_user_watches                   r,
              @{PROC}/ati/major                                         r,
              @{PROC}/pressure/*                                        r,
              @{PROC}/[0-9]*/fd/*                                       rw,
              @{PROC}/version                                           r,

              /dev/                                                     r,
              /dev/**                                                   rw,
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

              /run/udev/                                                ixr,
              /run/udev/**                                              ixr,
              /run/mount/                                               ixr,
              /run/mount/**                                             ixr,
              /run/current-system/sw/bin/*                              lr,
              /run/systemd/resolve/*                                    r,

              @{ETC}/static/                                            r,
              @{ETC}/static/**                                          r,
              @{ETC}/chromium/**                                        r,
              @{ETC}/host/                                              r,
              @{ETC}/host/**                                            r,

         @{ETC}/opt/                                                    rix,
         @{ETC}/opt/**                                                  rix,
         @{ETC}/static/opt/                                             rix,
         @{ETC}/static/opt/**                                           rix,
         @{ETC}/xdg/mimeapps.list                                       lr,
         @{ETC}/static/xdg/mimeapps.list                                lr,

        owner @{HOME}                                                   r,
        owner @{HOME}/.DCOPserver_*                                     r,
        owner @{HOME}/.ICEauthority                                     r,
        owner @{HOME}/.nix-profile/                                     r,
        owner @{HOME}/.nix-profile/**                                   r,
        owner @{HOME}/.fonts.*                                          lrw,
        owner @{HOME}/.cache/                                           wrk,
        owner @{HOME}/.cache/**                                         wrk,
        owner @{HOME}/.config/google-chrome                             rwkm,
        owner @{HOME}/.config/google-chrome/**                          rwkm,
        owner @{HOME}/.config/**                                        rwkm,
        owner @{HOME}/.config/                                          rw,

        owner @{HOME}/.local/                                           rw,
        owner @{HOME}/.local/**                                         rw,
        owner @{HOME}/.local/share/mime/mime.cache                      rw,
        owner @{HOME}/.local/share/applications/mimeapps.list           rw,
        owner @{HOME}/.pki/                                             rwkm,
        owner @{HOME}/.pki/**                                           rwkm,
        owner @{HOME}/Downloads/                                        rw,
        owner @{HOME}/Downloads/**                                      rw,

        owner @{HOME}/Unsafe\ share/                                    rw,
        owner @{HOME}/Unsafe\ share/**                                  rw,
        owner @{HOME}/tmp/**                                            rwkl,
        owner @{HOME}/tmp/                                              rw,


        @{ETC}/profiles/                                                r,
        @{ETC}/profiles/**                                              r,
        @{NIX}/var/                                                     r,
        @{NIX}/var/**                                                   r,
        @{RUN}/givc/**                                                  rix,

        owner @{run}/user/[0-9]*/                                       rw,
        owner @{run}/user/[0-9]*/**                                     rw,
              @{run}/user/[0-9]*/                                       r,
              @{run}/user/[0-9]*/**                                     r,

              /var/tmp/                                                 rw,
        owner /var/tmp/**                                               rwkl,

              /tmp/                                                     rw,
        owner /tmp/**                                                   rwkl,
              /tmp/.X[0-9]*-lock                                        r,
              /tmp/.X11-unix                                            r,
              /tmp/.XIM-unix                                            r,

        deny /boot/EFI/systemd/**                                       r,
        deny /boot/EFI/nixos/**                                         r,
        deny /boot/loader/**                                            r,
        deny /boot/vmlinuz*                                             r,
        deny /var/cache/fontconfig/                                     w,

        ### Networking ###
        network inet     stream,
        network inet6    stream,
        network inet     dgram,
        network inet6    dgram,
        network netlink  raw,
      }
    '';
  };

}

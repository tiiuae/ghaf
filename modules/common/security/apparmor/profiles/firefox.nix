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
        owner @{PROC}/@{pid}/gid_map                                   w,
        owner @{PROC}/@{pid}/setgroups                                 w,
        owner @{PROC}/@{pid}/uid_map                                   w,
      }
    ''
    else ''
      }
    '';
in {
  ## Option to enable Apparmor profile for Firefox
  options.ghaf.security.apparmor.apps.firefox = {
    enable = lib.mkOption {
      description = ''
        Enable firefox AppArmor profile.
      '';
      type = lib.types.bool;
      default = false;
    };
  };

  ## Apparmor profile for Firefox
  config.security.apparmor.policies."bin.firefox" = lib.mkIf cfg.apps.firefox.enable {
    profile =
      ''
        abi <abi/3.0>,
        include <tunables/global>

        @{MOZ_LIBDIR} = ${pkgs.firefox}/lib/firefox{,-esr}
        @{MOZ_HOMEDIR} = @{HOME}/.mozilla
        @{CACHEDIR} = @{HOME}/.cache
        @{MOZ_CACHEDIR} = @{CACHEDIR}/mozilla
        @{FIREFOX} = ${pkgs.firefox}/bin/firefox
        @{INTEGER}=[0-9]{[0-9],}{[0-9],}{[0-9],}{[0-9],}{[0-9],}{[0-9],}{[0-9],}{[0-9],}{[0-9],}
        @{ETC}=/etc
        @{NIX_STORE}=/nix/store

        profile firefox  @{FIREFOX} flags=(enforce){
           include <abstractions/base>
           include <abstractions/audio>
           include <abstractions/cups-client>
           include <abstractions/dbus-session>
           include <abstractions/gnome>
           include <abstractions/ibus>
           include <abstractions/kde>
           include <abstractions/nameservice>

           include "${pkgs.apparmorRulesFromClosure {name = "firefox";} [pkgs.firefox]}"

           # Uncomment these, if kernel.unprivileged_userns_clone = 1
           #capability sys_admin,
           #capability sys_chroot,
           #owner @{PROC}/@{pid}/gid_map                                   w,
           #owner @{PROC}/@{pid}/setgroups                                 w,
           #owner @{PROC}/@{pid}/uid_map                                   w,

           ${config.environment.etc."os-release".source}                   r,
           ${config.environment.etc."lsb-release".source}                  r,

           @{ETC}/nixos/**                                                 r,
           @{ETC}/nix/**                                                   r,
           @{NIX_STORE}/**                                                 mr,

           @{sys}/kernel/mm/transparent_hugepage/hpage_pmd_size            r,
           @{sys}/devices/system/cpu/present                               r,
           @{sys}/devices/system/cpu/cpu[0-9]/cache/index[0-9]/size        r,
           @{sys}/bus/pci                                                  rw,
           @{sys}/bus/pci_express                                          rw,
           @{sys}/bus/pci/devices/                                         rw,
           @{sys}/bus/pci/devices/**                                       rw,
           @{sys}/devices/pci*/**                                          rw,
           /tmp/.X[0-9]*-lock                                              r,

           @{FIREFOX}                                                      mrix,
           ${pkgs.firefox}/lib/firefox/firefox                             rix,
           ${pkgs.firefox}/lib/firefox/glxtest                             rix,
           ${pkgs.firefox}/lib/firefox/firefox-bin                         rix,
           ${pkgs.firefox}/lib/firefox/*.so                                mr,
           ${pkgs.firefox}/share/firefox/{,**}                             r,
           ${pkgs.firefox}/share/firefox/fonts                             r,
           ${pkgs.firefox}/lib/mozilla/plugins/                            r,
           ${pkgs.firefox}/lib/mozilla/plugins/libvlcplugin.so             mr,

           ${pkgs.firefox-unwrapped}/lib/firefox/glxtest                   rix,
           ${pkgs.firefox-unwrapped}/lib/firefox/firefox                   rix,
           ${pkgs.firefox-unwrapped}/lib/firefox/firefox-bin               rix,
           ${pkgs.firefox-unwrapped}/lib/firefox/*.so                      mr,
           ${pkgs.firefox-unwrapped}/lib/firefox/fonts                     r,
           ${pkgs.firefox-unwrapped}/lib/firefox/pingsender                r,
           ${pkgs.firefox-unwrapped}/share/firefox/{,**}                   r,
           ${pkgs.firefox-unwrapped}/lib/mozilla/plugins/                  r,
           ${pkgs.firefox-unwrapped}/lib/mozilla/plugins/libvlcplugin.so   mr,

                 @{PROC}/@{pid}/net/ipv6_route                             r,
                 @{PROC}/@{pid}/net/arp                                    r,
                 @{PROC}/@{pid}/net/if_inet6                               r,
                 @{PROC}/@{pid}/net/route                                  r,
                 @{PROC}/@{pid}/net/ipv6_route                             r,
           owner @{PROC}/@{pid}/cgroup                                     r,
           owner @{PROC}/@{pid}/fd/                                        r,
           owner @{PROC}/@{pid}/mountinfo                                  r,
           owner @{PROC}/@{pid}/mounts                                     r,
           owner @{PROC}/@{pid}/oom_score_adj                              w,
           owner @{PROC}/@{pid}/smaps                                      r,
           owner @{PROC}/@{pid}/stat                                       r,
           owner @{PROC}/@{pid}/statm                                      r,
           owner @{PROC}/@{pid}/task/                                      r,
           owner @{PROC}/@{pid}/task/@{tid}/comm                           rw,
           owner @{PROC}/@{pid}/task/@{tid}/stat                           r,
           owner @{PROC}/@{pids}/cmdline                                   r,
           owner @{PROC}/@{pids}/environ                                   r,
           owner @{PROC}/self/*                                            r,
           owner @{PROC}/self/fd/*                                         rw,

                 /dev/fb0                                                  rw,
                 /dev/                                                     r,
                 /dev/hidraw@{INTEGER}                                     rw,
                 /dev/shm/                                                 r,
                 /dev/tty                                                  rw,
                 /dev/video@{INTEGER}                                      rw,
           owner /dev/shm/org.chromium.*                                   rw,
           owner /dev/shm/org.mozilla.ipc.@{pid}.@{INTEGER}                rw,
           owner /dev/shm/wayland.mozilla.ipc.@{INTEGER}                   rw,
           owner /dev/tty@{INTEGER}                                        rw,

           owner @{MOZ_HOMEDIR}/                                           rw,
           owner @{MOZ_HOMEDIR}/{extensions,systemextensionsdev}/          rw,
           owner @{MOZ_HOMEDIR}/firefox/                                   rw,
           owner @{MOZ_HOMEDIR}/firefox/installs.ini                       rw,
           owner @{MOZ_HOMEDIR}/firefox/profiles.ini                       rw,
           owner @{MOZ_HOMEDIR}/firefox/*/                                 rw,
           owner @{MOZ_HOMEDIR}/firefox/*/**                               rwk,
           owner @{HOME}/.cache/                                           rw,
           owner @{MOZ_CACHEDIR}/                                          rw,
           owner @{MOZ_CACHEDIR}/**                                        rwk,
           owner @{CACHEDIR}/mesa_shader_cache/index                       wr,
           owner @{run}/user/1000/                                         rw,
           owner @{run}/user/1000/**                                       rw,
           owner /tmp/**                                                   m,
           owner /var/tmp/**                                               m,

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

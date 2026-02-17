# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay patches packages in nixpkgs, and adds in some of the ghaf's
# packages.
#
# keep-sorted start skip_lines=1
(final: prev: {
  cosmic-applets = import ./cosmic/cosmic-applets { inherit prev; };
  cosmic-comp = import ./cosmic/cosmic-comp { inherit prev; };
  cosmic-greeter = import ./cosmic/cosmic-greeter { inherit prev; };
  cosmic-initial-setup = import ./cosmic/cosmic-initial-setup { inherit prev; };
  cosmic-osd = import ./cosmic/cosmic-osd { inherit prev; };
  cosmic-settings = import ./cosmic/cosmic-settings { inherit prev; };
  cosmic-settings-daemon = import ./cosmic/cosmic-settings-daemon { inherit prev; };
  element-desktop = import ./element-desktop { inherit prev; };
  gtklock = import ./gtklock { inherit prev; };
  intel-gpu-tools = import ./intel-gpu-tools { inherit prev; };
  libfm = import ./libfm { inherit prev; };
  nvidia-jetpack = import ./nvidia-jetpack { inherit final prev; };
  osquery-with-hostname = import ./osquery-with-hostname { inherit prev; };
  papirus-icon-theme = import ./papirus-icon-theme { inherit prev; };
  qemu_kvm = import ./qemu { inherit final prev; };
  systemd = import ./systemd { inherit prev; };
  tpm2-pkcs11 = import ./tpm2-pkcs11 { inherit prev; };
  tpm2-tools = import ./tpm2-tools { inherit prev; };
  xdg-desktop-portal-cosmic = import ./cosmic/xdg-desktop-portal-cosmic { inherit prev; };
})
# keep-sorted end

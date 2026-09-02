# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay patches packages in nixpkgs, and adds in some of the ghaf's
# packages.
#
# keep-sorted start skip_lines=1
(_final: prev: {
  aggregateModules = import ./aggregate-modules-compat { inherit prev; };
  blueman = import ./blueman-applet { inherit prev; };
  chromium = import ./chromium { inherit prev; };
  cosmic-applets = import ./cosmic/cosmic-applets { inherit prev; };
  cosmic-comp = import ./cosmic/cosmic-comp { inherit prev; };
  cosmic-ext-calculator = import ./cosmic/cosmic-ext-calculator { inherit prev; };
  cosmic-greeter = import ./cosmic/cosmic-greeter { inherit prev; };
  cosmic-initial-setup = import ./cosmic/cosmic-initial-setup { inherit prev; };
  cosmic-osd = import ./cosmic/cosmic-osd { inherit prev; };
  cosmic-panel = import ./cosmic/cosmic-panel { inherit prev; };
  cosmic-reader = import ./cosmic/cosmic-reader { inherit prev; };
  cosmic-settings = import ./cosmic/cosmic-settings { inherit prev; };
  cosmic-settings-daemon = import ./cosmic/cosmic-settings-daemon { inherit prev; };
  element-desktop = import ./element-desktop { inherit prev; };
  grafana-alloy = import ./grafana-alloy { inherit prev; };
  intel-gpu-tools = import ./intel-gpu-tools { inherit prev; };
  libsForQt5 = import ./libsForQt5 { inherit prev; };
  mbrola-voices = import ./mbrola-voices { inherit prev; };
  osquery-with-hostname = import ./osquery-with-hostname { inherit prev; };
  papirus-icon-theme = import ./papirus-icon-theme { inherit prev; };
  pipewire = import ./pipewire { inherit prev; };
  qt6Packages = import ./qt6Packages { inherit prev; };
  spire4ghaf = import ./spire4ghaf { inherit prev; };
  tuned = import ./tuned { inherit prev; };
  udiskie = import ./udiskie { inherit prev; };
  waypipe = import ./waypipe { inherit prev; };
  yad = import ./yad { inherit prev; };
})
# keep-sorted end

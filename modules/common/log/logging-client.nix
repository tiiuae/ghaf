# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  hostName,
  ...
}: {
  environment.systemPackages = [pkgs.grafana-alloy];
  # Import Grafana Alloy for remote upload of journal logs
  imports = [
    (import ./grafana-alloy.nix {
      inherit pkgs;
      hostName = "${hostName}";
    })
  ];
}

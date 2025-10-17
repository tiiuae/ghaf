# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay is for specific fixes needed only to enable cross-compilation.
#
final: prev:
let
  grafanaAlloyOverlay = import ./grafana-alloy.nix final prev;
in
{
  #   v4l-utils = import ./v4l-utils { inherit final prev; };
  inherit (grafanaAlloyOverlay) grafana-alloy;
}

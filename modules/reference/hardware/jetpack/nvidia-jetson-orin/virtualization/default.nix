# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  imports = [
    ./nv-preprocess-dtsi.nix
    ./common/bpmp-virt-common
    ./host/bpmp-virt-host
    ./host/uarta-host
    ./passthrough/uarti-net-vm
    ./passthrough/mgbe0-net-vm
    ./passthrough/gpu-vm
    ./passthrough/disp-vm
    ./passthrough/gui-vm
    ./pkvm
    ./ownership-assertions.nix
  ];
}

# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Closed BPMP host-proxy allow-list, shared verbatim by gpu-vm and gui-vm.
# Extracted unchanged from gpu-vm/default.nix so both the compute-with-host1x
# (gpu-vm) and the combined GPU+display (gui-vm) VMs consume one source of truth.
# PR2055 proved this exact list already covers BOTH compute AND display (disp-vm
# relies on gpu-vm's allow-list), so there is nothing VM-specific to parameterize.
#
# BPMP allow-list: union of the bpmp ids the passed-through compute engines
# declare in the live host DT (only cells whose phandle is &bpmp):
#   gpu@17000000    clocks 304 41 236   reset 19    pd 35
#   host1x@13e00000 clocks 46 1
#   vic@15340000    clock 167           reset 113   pd 29
#   nvdec@15480000  clocks 83 40 154    reset 44    pd 23
#   nvjpg@15540000  clock 20            reset 10    pd 36
# display@13800000 is host-side now, so the guest no longer requests these display
# ids, but they stay in the closed allow-list (still NOT allow-all) so it need not
# change if the guest re-acquires a display path. They are the exact ids the guest
# display@13800000 node declares. dce@d800000 needs no ids (host owns the real DCE;
# the guest's synthetic dce node has no clocks). The host proxy logging "clock not
# allowed" for probed parent PLLs is the boundary working; add an id only if
# display/GPU init actually fails on that denied id.
{
  # compute engines (see per-device breakdown above)
  clocks = [
    1
    20
    40
    41
    46
    83
    154
    167
    236
    304
  ]
  # 13800000.display: nvdisplayhub/disp/p0/p1, dpaux, fuse, the DSI/SP/V
  # PLL tree, RG/SOR/SF paths, mipi-cal, osc, dsc, maud, aza.
  ++ [
    # Root parents of the SOR clock tree. The guest's clk_prepare_enable on sor0
    # propagates enables up to these; a denied parent fails the WHOLE chain, so
    # the SOR never turns on (no video despite a completed modeset). Host-critical
    # always-on roots: a guest enable is a BPMP refcount no-op, and the guest runs
    # clk_ignore_unused so it never mass-disables them.
    14 # TEGRA234_CLK_CLK_M
    102 # TEGRA234_CLK_PLLP_OUT0
    19
    40
    71
    72
    84
    85
    86
    87
    88
    91
    125
    126
    127
    128
    129
    130
    132
    162
    178
    179
    180
    181
    182
    183
    184
    # NOTE: the guest display RM also probes host-critical clocks during its
    # clock-tree walk (429-434=CPU DSU/SCE/RCE/DCE_CPU, 472=MCHUB, etc). Those
    # denials are CORRECT and HARMLESS (host already runs them) and must STAY
    # denied -- never add CPU/coprocessor/memory clocks here. The list above is
    # exactly the 62 clock ids the guest display@13800000 node declares.
    435
    436
    437
    438
    439
    440
    441
    442
    443
    444
    445
    446
    447
    448
    449
    450
    451
    452
    453
    454
    455
    456
    457
    458
    459
    460
    461
    462
    463
    464
    465
    466
    467
    468
    469
    470
    471
  ];
  # compute resets ++ display (nvdisplay 16, dpaux 8, dsi-core 3, mipi-cal 37)
  resets = [
    10
    19
    44
    113
  ]
  ++ [
    3
    8
    16
    37
  ];
  # compute power-domains ++ display DISP (3)
  powerDomains = [
    23
    29
    35
    36
  ]
  ++ [ 3 ];
}

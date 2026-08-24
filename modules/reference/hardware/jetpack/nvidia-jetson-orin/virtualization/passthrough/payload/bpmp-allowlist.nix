# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Per-capability BPMP resources.
# Live-DT compute resources:
#   gpu@17000000    clocks 304 41 236   reset 19    pd 35
#   host1x@13e00000 clocks 46 1
#   vic@15340000    clock 167           reset 113   pd 29
#   nvdec@15480000  clocks 83 40 154    reset 44    pd 23
#   nvjpg@15540000  clock 20            reset 10    pd 36
let
  compute = {
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
    ];
    resets = [
      10
      19
      44
      113
    ];
    powerDomains = [
      23
      29
      35
      36
    ];
  };
  display = {
    # display@13800000 clocks
    clocks = [
      # SOR root parents
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
      # Keep host-critical CPU, coprocessor, and memory clocks denied.
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
    resets = [
      3
      8
      16
      37
    ];
    powerDomains = [ 3 ];
  };
  combine = left: right: {
    clocks = left.clocks ++ right.clocks;
    resets = left.resets ++ right.resets;
    powerDomains = left.powerDomains ++ right.powerDomains;
  };
in
{
  inherit compute display;
  combined = combine compute display;
}

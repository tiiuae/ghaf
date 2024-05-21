# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellApplication,
  lib,
  ...
}:
writeShellApplication {
  name = "perf-test-icicle-kit";
  text = ''
    time {
    perf bench sched messaging;
    perf bench sched pipe -l 50000;
    perf bench syscall basic;
    perf bench mem memcpy;
    perf bench mem memset;
    perf bench mem find_bit -i 5 -j 1000;
    perf bench numa mem -p 1 -t 1 -P 1024 -C 0 -M 0 -s 5 -zZq --thp 1 --no-data_rand_walk;
    perf bench futex all;
    perf bench epoll wait;
    perf bench epoll ctl;
    perf bench internals synthesize -i 1000;
    perf bench internals kallsyms-parse -i 10;
    } | tee -a perf_results_YYYY-MM-DD_BUILDER-BuildID_SDorEMMC
  '';
  meta = with lib; {
    description = "Perf test script customized for measuring ghaf performance on Microchip Icicle Kit target";
  };
}

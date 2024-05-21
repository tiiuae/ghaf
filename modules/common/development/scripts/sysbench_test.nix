# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellApplication,
  lib,
  ...
}:
writeShellApplication {
  name = "sysbench-test";
  text = ''
    # Threads variable needs to be given on the command line.
    # For example: ./sysbench_simplified_test 20
    THREADS="''$1"

    # Create a directory for the results with a timestamp
    RESULT_DIR="sysbench_results"
    echo -e "\nCreating directory for test results:"
    echo "./''$RESULT_DIR"
    mkdir -p ''$RESULT_DIR

    # Create test_info file with information about the run environment: lscpu, free, df
    echo -e "\nSaving information about test environment to ./''$RESULT_DIR/test_info\n"
    echo -e "''$(lscpu)" "\n\n" "''$(free)" "\n\n" "''$(df)" "\n\n" >> ./''$RESULT_DIR/test_info

    echo -e "\nHost: ''$(hostname)\n" | tee -a ./''$RESULT_DIR/test_info

    # cpu tests
    echo -e "\nRunning CPU tests...\n"
    sysbench cpu --time=10 --threads=1 --cpu-max-prime=20000 run | tee ./''$RESULT_DIR/cpu_1thread_report
    if [ "''$THREADS" -gt 1 ]
    then
        sysbench cpu --time=10 --threads="''${THREADS}" --cpu-max-prime=20000 run | tee ./''$RESULT_DIR/cpu_report
    fi

    # memory tests
    echo -e "\nRunning memory tests...\n"
    sysbench memory --time=60 --memory-oper=read --threads=1 run | tee ./''$RESULT_DIR/memory_read_1thread_report
    sysbench memory --time=60 --memory-oper=write --threads=1 run | tee ./''$RESULT_DIR/memory_write_1thread_report
    if [ "''$THREADS" -gt 1 ]
    then
        sysbench memory --time=15 --memory-oper=read --threads="''${THREADS}" run | tee ./''$RESULT_DIR/memory_read_report
        sysbench memory --time=30 --memory-oper=write --threads="''${THREADS}" run | tee ./''$RESULT_DIR/memory_write_report
    fi

    echo -e "\nTest finished.\n"
  '';
  meta = with lib; {
    description = "Script for sysbench tests (excluding fileio)";
  };
}

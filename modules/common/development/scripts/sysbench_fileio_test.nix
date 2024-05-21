# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellApplication,
  lib,
  ...
}:
writeShellApplication {
  name = "sysbench-fileio-test";
  text = ''
    # Test set to be run with sysbench

    # These variable needs to be given on the command line. For example: sysbench-fileio-test 20
    THREADS="''$1"

    # Create a directory for the results
    RESULT_DIR="sysbench_results"
    echo -e "\nCreating directory for test results:\n./''$RESULT_DIR"
    mkdir -p ''$RESULT_DIR

    # Create test_info file with system information
    echo -e "\nSaving information about test environment to ./''$RESULT_DIR/test_info\n"
    echo -e "''$(lscpu)" "\n\n" "''$(free)" "\n\n" "''$(df)" "\n\n" >> ./''$RESULT_DIR/test_info
    echo -e "\nHost: ''$(hostname)\n" | tee -a ./''$RESULT_DIR/test_info

    # Calculate total memory in kB and set FILE_TOTAL_SIZE 4GB higher than the total memory
    TOTAL_MEM_kB=''$(free | awk -F: 'NR==2 {print ''$2}' | awk '{print ''$1}')
    FILE_TOTAL_SIZE_kB=''$((TOTAL_MEM_kB + 4000000))

    # Read available disk space in kB and check for sufficient disk space
    AVAILABLE_DISK_SPACE_kB=''$(df | grep -w "/" | awk '{print ''$4}')
    if [ ''$((FILE_TOTAL_SIZE_kB + FILE_TOTAL_SIZE_kB / 10)) -gt "''$AVAILABLE_DISK_SPACE_kB" ]; then
        echo -e "\nInsufficient disk space for fileio test." | tee -a ./''$RESULT_DIR/test_info
        exit 1
    fi

    echo -e "\nDetected available total memory ''${TOTAL_MEM_kB} kB." | tee -a ./''$RESULT_DIR/test_info
    echo -e "\nDetected available disk space ''${AVAILABLE_DISK_SPACE_kB} kB." | tee -a ./''$RESULT_DIR/test_info
    echo -e "\nStarting fileio test with FILE_TOTAL_SIZE=''${FILE_TOTAL_SIZE_kB} kB." | tee -a ./''$RESULT_DIR/test_info

    # Execute sysbench fileio tests if the checks passed
    sysbench fileio --file-total-size=''${FILE_TOTAL_SIZE_kB}K --threads="''${THREADS}" --file-test-mode=seqrd prepare
    sysbench fileio --file-total-size=''${FILE_TOTAL_SIZE_kB}K --threads="''${THREADS}" --file-test-mode=seqrd --time=30 run | tee ./''$RESULT_DIR/fileio_rd_report
    sysbench fileio cleanup
    sysbench fileio --file-total-size=''${FILE_TOTAL_SIZE_kB}K --threads="''${THREADS}" --file-test-mode=seqwr --time=30 run | tee ./''$RESULT_DIR/fileio_wr_report
    sysbench fileio cleanup

    echo -e "\nTest finished.\n"
  '';
  meta = with lib; {
    description = "Script for sysbench fileio tests";
  };
}

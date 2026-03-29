# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Virtiofs integration tests module
#
# Usage (from host):
#   virtiofs-test              # Interactive menu
#   virtiofs-test --basic      # Run basic tests
#   virtiofs-test --all        # Run all tests
#   virtiofs-test basic.rw     # Run specific test
#   virtiofs-test --list       # List available tests
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.development.virtiofs-tests;

  isHost = config.ghaf.type == "host";
  guivmEnabled = config.ghaf.virtualization.microvm.guivm.enable or false;
  sharedDirCfg = config.ghaf.storage.shared-directories;
  channels = sharedDirCfg.channels or { };

  # Use gui-vm as the single test VM, host as the counterpart
  testVm = "gui-vm";

  # Channel finders for each test type
  # rw: gui-vm is readWrite with at least one other readWrite participant
  findRwChannel = lib.findFirst (
    name:
    let
      ch = channels.${name};
      rwParticipants = lib.attrNames (ch.readWrite or { });
    in
    lib.elem testVm rwParticipants && lib.length rwParticipants >= 2
  ) null (lib.attrNames channels);

  # ro: gui-vm is readOnly (tests that readOnly can't write/propagate)
  findRoChannel = lib.findFirst (
    name:
    let
      ch = channels.${name};
    in
    (ch.readOnly or { }) ? ${testVm}
  ) null (lib.attrNames channels);

  # wo: gui-vm is writeOnly (tests write-only semantics)
  findWoChannel = lib.findFirst (
    name:
    let
      ch = channels.${name};
    in
    (ch.writeOnly or { }) ? ${testVm}
  ) null (lib.attrNames channels);

  # Build config for rw test: verify propagation to another writer's share
  mkRwConfig =
    let
      chName = findRwChannel;
      ch = if chName != null then channels.${chName} else null;
      vmCfg = if ch != null then ch.readWrite.${testVm} or null else null;
      # Need at least one other readWrite participant for propagation testing
      otherWriters = lib.filter (n: n != testVm) (lib.attrNames (ch.readWrite or { }));
      hasOtherWriter = otherWriters != [ ];
      # Host verifies at channel base path (TestContext constructs share/, export/ internally)
      hostVerifyPath = "${sharedDirCfg.baseDirectory}/${chName}";
    in
    lib.optionalAttrs (vmCfg != null && hasOtherWriter) {
      host_path = hostVerifyPath;
      vm = testVm;
      vm_path = vmCfg.mountPoint;
    };

  # Build config for ro test: verify nothing propagates (gui-vm is read-only)
  mkRoConfig =
    let
      chName = findRoChannel;
      ch = if chName != null then channels.${chName} else null;
      vmCfg = if ch != null then ch.readOnly.${testVm} or null else null;
      hostVerifyPath = if chName != null then "${sharedDirCfg.baseDirectory}/${chName}" else null;
    in
    lib.optionalAttrs (vmCfg != null && hostVerifyPath != null) {
      host_path = hostVerifyPath;
      vm = testVm;
      vm_path = vmCfg.mountPoint;
    };

  # Build config for wo test: gui-vm writes to write-only channel
  # Host can verify at export that content arrived (even if no specific verification needed)
  mkWoConfig =
    let
      chName = findWoChannel;
      ch = if chName != null then channels.${chName} else null;
      vmCfg = if ch != null then ch.writeOnly.${testVm} or null else null;
      # Host verifies at channel base path (TestContext constructs share/, export/ internally)
      hostVerifyPath = if chName != null then "${sharedDirCfg.baseDirectory}/${chName}" else null;
    in
    lib.optionalAttrs (vmCfg != null) {
      host_path = hostVerifyPath;
      vm = testVm;
      vm_path = vmCfg.mountPoint;
    };

  testConfig = {
    # Only include channels if gui-vm is enabled
    channels = lib.optionalAttrs guivmEnabled (
      lib.filterAttrs (_: v: v != { }) {
        rw = mkRwConfig;
        ro = mkRoConfig;
        wo = mkWoConfig;
      }
    );
    vms = lib.optionalAttrs guivmEnabled {
      ${testVm} = {
        user = "ghaf";
        password = "ghaf";
      };
    };
  };

  testConfigFile = pkgs.writeText "virtiofs-test-config.json" (builtins.toJSON testConfig);

  hasAllChannels = testConfig.channels ? rw && testConfig.channels ? ro && testConfig.channels ? wo;
  canEnable = guivmEnabled && hasAllChannels;

  # Test wrapper script
  virtiofs-test = pkgs.writeShellApplication {
    name = "virtiofs-test";
    runtimeInputs = [
      pkgs.ghaf-virtiofs-tests
      pkgs.sshpass
      pkgs.jq
    ];
    text = ''
      CONFIG="/etc/virtiofs-test-config.json"

      # Available tests
      BASIC_TESTS="basic.rw basic.ro basic.wo basic.modify basic.delete basic.rename basic.scan basic.performance"
      EXTENDED_TESTS="extended.paths extended.permissions extended.symlink extended.ignore extended.large_file extended.quarantine extended.rename_rapid extended.scan_overhead"
      SECURITY_TESTS="security.bypass security.overload"
      VSOCK_TESTS="vsock.scan vsock.proxy vsock.performance vsock.security"

      usage() {
        echo "Virtiofs Integration Tests"
        echo ""
        echo "Usage: virtiofs-test [OPTIONS] [TEST]"
        echo ""
        echo "Options:"
        echo "  --list       List all available tests"
        echo "  --basic      Run basic tests only"
        echo "  --extended   Run extended tests"
        echo "  --security   Run security tests"
        echo "  --vsock      Run vsock tests"
        echo "  --all        Run all tests"
        echo "  --clean      Clean up test files only"
        echo "  --help       Show this help"
        echo ""
        echo "Tests:"
        echo "  Basic:     $BASIC_TESTS"
        echo "  Extended:  $EXTENDED_TESTS"
        echo "  Security:  $SECURITY_TESTS"
        echo "  Vsock:     $VSOCK_TESTS"
        echo ""
        echo "Examples:"
        echo "  virtiofs-test --basic      # Run all basic tests"
        echo "  virtiofs-test basic.rw     # Run specific test"
        echo "  virtiofs-test              # Interactive selection"
      }

      NEEDS_CLEANUP=false
      cleanup() {
        if [[ "$NEEDS_CLEANUP" == "true" ]]; then
          echo ""
          echo "Cleaning up test files..."
          echo "========================================"
          # Extract host_path values from config and clean each
          for path in $(jq -r '.channels[].host_path // empty' "$CONFIG" 2>/dev/null); do
            if [[ -n "$path" && -d "$path" ]]; then
              echo "Cleaning: $path"
              ghaf-virtiofs-test clean "$path" || true
            fi
          done
        fi
      }
      trap cleanup EXIT

      run_tests() {
        NEEDS_CLEANUP=true
        local tests="$1"
        local failed=0
        for test in $tests; do
          echo ""
          echo "Running: $test"
          echo "========================================"
          if ! ghaf-virtiofs-test-runner -c "$CONFIG" --test "$test"; then
            echo "FAILED: $test"
            failed=$((failed + 1))
          fi
        done
        if [[ $failed -gt 0 ]]; then
          echo ""
          echo ""
          echo ""
          echo "========================================"
          echo "TEST FAILED: $failed test(s) failed"
          echo "========================================"
          return 1
        else
          echo ""
          echo ""
          echo ""
          echo "========================================"
          echo "ALL TESTS PASSED"
          echo "========================================"
          return 0
        fi
      }

      if [[ $# -eq 0 ]]; then
        echo "Select test category:"
        echo "  1) Basic tests"
        echo "  2) Extended tests"
        echo "  3) Security tests"
        echo "  4) Vsock tests"
        echo "  5) All tests"
        echo "  6) List tests"
        echo "  7) Clean up test files"
        echo ""
        read -r -p "Choice [1-7]: " choice
        case $choice in
          1) run_tests "$BASIC_TESTS" ;;
          2) run_tests "$EXTENDED_TESTS" ;;
          3) run_tests "$SECURITY_TESTS" ;;
          4) run_tests "$VSOCK_TESTS" ;;
          5) run_tests "$BASIC_TESTS $EXTENDED_TESTS $SECURITY_TESTS $VSOCK_TESTS" ;;
          6) ghaf-virtiofs-test-runner --list ;;
          7) NEEDS_CLEANUP=true ;;
          *) echo "Invalid choice"; exit 1 ;;
        esac
        exit
      fi

      case "$1" in
        --help|-h) usage ;;
        --list) ghaf-virtiofs-test-runner --list ;;
        --clean) NEEDS_CLEANUP=true ;;
        --basic) run_tests "$BASIC_TESTS" ;;
        --extended) run_tests "$EXTENDED_TESTS" ;;
        --security) run_tests "$SECURITY_TESTS" ;;
        --vsock) run_tests "$VSOCK_TESTS" ;;
        --all) run_tests "$BASIC_TESTS $EXTENDED_TESTS $SECURITY_TESTS $VSOCK_TESTS" ;;
        *) NEEDS_CLEANUP=true; ghaf-virtiofs-test-runner -c "$CONFIG" --test "$1" ;;
      esac
    '';
  };
in
{
  options.ghaf.development.virtiofs-tests = {
    enable = lib.mkEnableOption "virtiofs-tools integration tests";
  };

  config = lib.mkIf (cfg.enable && isHost) {
    warnings =
      lib.optional (!guivmEnabled) "virtiofs-tests: gui-vm is not enabled, tests disabled"
      ++ lib.optional (
        guivmEnabled && !hasAllChannels
      ) "virtiofs-tests: gui-vm must participate in rw, ro, and wo channels, tests disabled";

    environment.systemPackages = lib.mkIf canEnable [
      pkgs.ghaf-virtiofs-tests
      pkgs.sshpass
      virtiofs-test
    ];

    environment.etc."virtiofs-test-config.json" = lib.mkIf canEnable {
      source = testConfigFile;
    };
  };
}

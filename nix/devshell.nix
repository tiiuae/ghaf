# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, lib, ... }:
{
  imports = [
    inputs.devshell.flakeModule
    ./devshell/kernel.nix
  ];
  perSystem =
    {
      config,
      pkgs,
      system,
      ...
    }:
    {
      devshells = {
        # the main developer environment
        default = {
          devshell = {
            name = "Ghaf devshell";
            meta.description = "Ghaf development environment";
            packages =
              [
                pkgs.jq
                pkgs.mdbook
                pkgs.nix-eval-jobs
                pkgs.nix-fast-build
                pkgs.nix-output-monitor
                pkgs.nix-tree
                pkgs.nixVersions.latest
                pkgs.reuse
                config.treefmt.build.wrapper
                (pkgs.callPackage ../packages/flash { })
                (pkgs.callPackage ../packages/ghaf-build-helper { })
              ]
              ++ lib.attrValues config.treefmt.build.programs # make all the trefmt packages available
              ++ lib.optional (pkgs.hostPlatform.system != "riscv64-linux") pkgs.cachix;
          };
          commands = [
            {
              help = "Format";
              name = "format-repo";
              command = "treefmt";
              category = "checker";
            }
            {
              help = "Check license";
              name = "check-license";
              command = "reuse lint";
              category = "linters";
            }
            {
              help = "Ghaf nixos-rebuild command";
              name = "ghaf-rebuild";
              command = "ghaf-build-helper $@";
              category = "builder";
            }
          ];
        };

        smoke-test = {
          devshell = {
            name = "Ghaf smoke test";
            meta.description = "Ghaf smoke test environment";
            packagesFrom = [ inputs.ci-test-automation.devShell.${system} ];
          };

          commands = [
            {
              help = "
                Usage: smoke-test [ip] [device] [password] [test] [commit]
                Runs automated tests (only pre-merge tests by default) on the defined target.

                Required arguments:
                ip         IP address of the target device
                           (if running locally from ghaf-host of the target device use
                           127.0.0.1 for orin-agx
                           192.168.100.1 for lenovo-x1 and orin-nx)
                device     Device name of the target. Use exactly one of these options:
                           Lenovo-X1
                           Orin-AGX
                           Orin-NX
                           NUC
                password   Password for the ghaf user

                Optional arguments:
                test       Test tag which defines which test cases will be run.
                           Defaults to pre-merge.
                commit     This can be commit hash or any identifier.
                           Relevant only if running performance tests.
                           It will be used in presenting preformance test results in plots.
                           Defaults to smoke.
              ";
              name = "smoke-test";
              command = ''
                IP="''$1"
                DEVICE="''$2"
                PW="''$3"
                TEST_TAG="''${4:-pre-merge}"
                COMMIT="''${6:-smoke}"
                THREADS=8
                grep -q "X1" <<< "''$DEVICE" && THREADS=20
                grep -q "AGX" <<< "''$DEVICE" && THREADS=12
                if [ -d "./ci-test-automation" ]
                then
                    pwd
                    echo "Found existing ci-test-automation repository at ./"
                    echo "Pulling latest updates from the remote repository."
                    cd ./ci-test-automation ; git pull ; cd ../
                else
                    git clone https://github.com/tiiuae/ci-test-automation.git
                fi
                cd ci-test-automation/Robot-Framework/test-suites
                nix develop --command robot -v CONFIG_PATH:None -v DEVICE_IP_ADDRESS:''${IP} -v THREADS_NUMBER:''${THREADS} -v COMMIT_HASH:''${COMMIT} -v DEVICE:''${DEVICE} -v PASSWORD:''${PW} -i ''${DEVICE,,}AND''${TEST_TAG} ./
              '';
              category = "test";
            }
          ];
        };
      };
    };
}

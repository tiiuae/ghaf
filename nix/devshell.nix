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
      self',
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
                #TODO: can these be made available through pkgs?
                self'.legacyPackages.ghaf-build-helper
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
                Usage: robot-test -i [ip] -d [device] -p [password]
                                  -t [tag] -c [commit] -n [threads] -f [configpath] -o [outputdir]

                Runs automated tests (only pre-merge tests by default) on the defined target.

                Required arguments:
                -i  --ip          IP address of the target device
                                  (if running locally from ghaf-host of the target device use
                                  127.0.0.1 for orin-agx
                                  192.168.100.1 for lenovo-x1 and orin-nx)
                -d  --device      Device name of the target. Use exactly one of these options:
                                    Lenovo-X1
                                    Orin-AGX
                                    Orin-NX
                                    NUC
                -p  --password    Password for the ghaf user

                Optional arguments:
                -t  --tag         Test tag which defines which test cases will be run.
                                  Defaults to 'pre-merge'.
                -c  --commit      This can be commit hash or any identifier.
                                  Relevant only if running performance tests.
                                  It will be used in presenting preformance test results in plots.
                                  Defaults to 'smoke'.
                -n  --threads     How many threads the device has.
                                  This parameter is relevant only for performance tests.
                                  Defaults to
                                    20 with -d Lenovo-X1
                                    12 with -d Orin-AGX
                                    8 with other devices
                -f  --configpath  Path to config directory.
                                  Defaults to 'None'.
                -o  --outputdir   Path to directory where all helper files and result files are saved.
                                  Defaults to '/tmp/test_results'
              ";
              name = "robot-test";
              command = ''
                tag="pre-merge"
                commit="smoke"
                configpath="None"
                outputdir="/tmp/test_results"
                threads=8
                threads_manual_set=false

                while [ ''$# -gt 0 ]; do
                  if [[ ''$1 == "-i" || ''$1 == "--ip" ]]; then
                    ip="''$2"
                    shift
                  elif [[ ''$1 == "-d" || ''$1 == "--device" ]]; then
                    device="''$2"
                    shift
                  elif [[ ''$1 == "-p" || ''$1 == "--password" ]]; then
                    pw="''$2"
                    shift
                  elif [[ ''$1 == "-t" || ''$1 == "--tag" ]]; then
                    tag="''$2"
                    shift
                  elif [[ ''$1 == "-c" || ''$1 == "--commit" ]]; then
                    commit="''$2"
                    shift
                  elif [[ ''$1 == "-n" || ''$1 == "--threads" ]]; then
                    threads="''$2"
                    threads_manual_set=true
                    shift
                  elif [[ ''$1 == "-f" || ''$1 == "--config" ]]; then
                    configpath="''$2"
                    shift
                  elif [[ ''$1 == "-o" || ''$1 == "--outputdir" ]]; then
                    outputdir="''$2"
                    shift
                  else
                    echo "Unknown option: ''$1"
                    exit 1
                  fi
                  shift
                done

                if [[ ''${threads_manual_set} == false ]]; then
                  grep -q "X1" <<< "''$device" && threads=20
                  grep -q "AGX" <<< "''$device" && threads=12
                fi

                cd ${inputs.ci-test-automation.outPath}/Robot-Framework/test-suites
                ${
                  inputs.ci-test-automation.packages.${system}.ghaf-robot
                }/bin/ghaf-robot -v CONFIG_PATH:''${configpath} -v DEVICE_IP_ADDRESS:''${ip} -v THREADS_NUMBER:''${threads} -v COMMIT_HASH:''${commit} -v DEVICE:''${device} -v PASSWORD:''${pw} -i ''${device,,}AND''${tag} --outputdir ''${outputdir} .
              '';
              category = "test";
            }
            {
              help = "Show path to ci-test-automation repo in nix store";
              name = "robot-path";
              command = "echo ${inputs.ci-test-automation.outPath}";
              category = "test";
            }
          ];
        };
      };
    };
}

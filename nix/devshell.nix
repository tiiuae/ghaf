# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs, lib, ... }:
{
  imports = [
    inputs.devshell.flakeModule
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
            packages = [
              pkgs.jq
              pkgs.nodejs
              pkgs.nix-eval-jobs
              pkgs.nix-fast-build
              pkgs.nix-output-monitor
              pkgs.nix-tree
              pkgs.nixVersions.latest
              pkgs.reuse
              pkgs.prefetch-npm-deps
              config.treefmt.build.wrapper
              self'.legacyPackages.ghaf-build-helper
              self'.legacyPackages.flash-script
              self'.legacyPackages.update-docs-depends
              pkgs.cachix
            ]
            ++ config.pre-commit.settings.enabledPackages
            ++ lib.attrValues config.treefmt.build.programs; # make all the trefmt packages available

            startup.hook.text = config.pre-commit.installationScript;
          };
          commands = [
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
            {
              help = "Ghaf flash command";
              name = "ghaf-flash";
              command = "flash-script $@";
              category = "builder";
            }
            {
              help = "Update the npm dependencies in the docs";
              name = "update-docs-depends";
              command = "update-docs-deps";
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
                                  orin-agx
                                  orin-agx-64
                                  orin-nx
                                  lenovo-x1
                                  dell-7330
                                  darter-pro
                                  x1-sec-boot
                -p  --password    Password for the ghaf (admin) user

                Optional arguments:
                --username        Username
                                  Defaults to 'testuser'
                --userpasswd    Password for the normal user
                                  Defaults to 'testpw'
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
                username="testuser"
                userpasswd="testpw"

                while [ ''$# -gt 0 ]; do
                  case "''$1" in
                    (-i|--ip)        ip="''$2";;
                    (-d|--device)    device="''$2";;
                    (-p|--password)  pw="''$2";;
                    (--username)     username="''$2";;
                    (--userpasswd)   userpasswd="''$2";;
                    (-t|--tag)       tag="''$2";;
                    (-c|--commit)    commit="''$2";;
                    (--threads)      threads="''$2";;
                    (--config)       configpath="''$2";;
                    (--outputdir)    outputdir="''$2";;
                    (*)
                      echo "Unknown option: ''$1"
                      exit 1
                      ;;
                  esac
                  shift 2
                done

                if [[ ''${threads_manual_set} == false ]]; then
                  grep -q "x1" <<< "''$device" && threads=20
                  grep -q "agx" <<< "''$device" && threads=12
                  grep -q "darter-pro" <<< "''$device" && threads=16
                fi

                cd ${inputs.ci-test-automation.outPath}/Robot-Framework/test-suites
                ${
                  inputs.ci-test-automation.packages.${system}.ghaf-robot
                }/bin/ghaf-robot -v CONFIG_PATH:''${configpath} -v DEVICE_IP_ADDRESS:''${ip} -v THREADS_NUMBER:''${threads} -v COMMIT_HASH:''${commit} -v DEVICE:''${device} -v DEVICE_TYPE:''${device} -v PASSWORD:''${pw} -v USER_LOGIN:''${username} -v USER_PASSWORD:''${userpasswd} -i ''${device,,}AND''${tag} --outputdir ''${outputdir} .
              '';
              category = "test";
            }
            {
              help = "Show path to ci-test-automation repo in nix store";
              name = "robot-path";
              command = "echo ${inputs.ci-test-automation.outPath}";
              category = "test";
            }
            {
              help = "
                If running smoke tests locally from ghaf laptop target this
                command can be called after the test run to send the test
                report files to chrome-vm for visualization with the browser:
                file:///tmp/report.html

                Required arguments:
                --password    Password for the ghaf (admin) user
                --resultdir   Path to the result files
              ";
              name = "results-send";
              command = ''
                while [ ''$# -gt 0 ]; do
                  case "''$1" in
                    (--password)   password="''$2";;
                    (--resultdir)  resultdir="''$2";;
                    (*)
                      echo "Unknown option: ''$1"
                      exit 1
                      ;;
                  esac
                  shift 2
                done

                python ${inputs.ci-test-automation.outPath}/Robot-Framework/lib/send_report.py ''${password} ''${resultdir}
              '';
              category = "test";
            }
          ];
        };
      };
    };
}

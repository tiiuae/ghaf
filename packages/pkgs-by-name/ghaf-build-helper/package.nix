# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Helper script use nixos-rebuild without persistent
# changes of the ssh configuration.
#
# To use nixos-rebuild directly, add the following
# to your configuration on your development machine:
#
# programs = {
#   ssh = {
#     startAgent = true;
#     extraConfig = ''
#       host ghaf-netvm
#         user root
#         hostname <target-ip>
#       host ghaf-host
#          user root
#          hostname 192.168.100.2
#          proxyjump ghaf-netvm
#     '';
#   };
# };
#
# or export the NIX_SSHOPTS environment variable:
#
# export NIX_SSHOPTS="-o ProxyJump=root@<your-target-ip>"
#
{
  writeShellApplication,
  nixos-rebuild,
  ipcalc,
}:
writeShellApplication {
  name = "ghaf-build-helper";
  runtimeInputs = [ nixos-rebuild ];
  text = ''
        function script_usage() {
          cat << EOF

    Usage:   ghaf-rebuild <target-ip> <flake-target> [nixos-rebuild options]

    Options:
      -h, --help         Show this help message and exit

      --force-remote     Force the build to be performed on a configured remote builder.
                         Adds: --max-jobs 0

      --force-local      Force the build to be performed on the local machine.
                         Adds: --builders ""

      *                  Any additional options are passed directly to nixos-rebuild.
                         See https://nixos.wiki/wiki/Nixos-rebuild or run nixos-rebuild --help.

    Examples:
      ghaf-rebuild 192.168.0.123 .#lenovo-x1-carbon-gen11-debug switch
      ghaf-rebuild 192.168.0.123 .#lenovo-x1-carbon-gen11-debug --force-local switch

    EOF
        }

        if [ $# -le 2 ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
          script_usage
          exit 0
        fi

        proxy_jump="$1"
        if ! ${ipcalc}/bin/ipcalc -c "$proxy_jump"; then
          echo "Invalid IP address: $proxy_jump"
          exit 1
        fi
        build_target="$2"
        shift 2

        # Parse flags
        args=()
        for arg in "$@"; do
          case "$arg" in
            --force-remote)
              args+=(--max-jobs 0)
              ;;
            --force-local)
              args+=(--builders \'\')
              ;;
            *)
              args+=("$arg")
              ;;
          esac
        done

        export NIX_SSHOPTS="-o ProxyJump=root@$proxy_jump"
        nixos-rebuild --flake "$build_target" --target-host root@ghaf-host --no-reexec "''${args[@]}"
  '';
  meta = {
    description = "Helper script to use nixos-rebuild without persistent changes of the ssh configuration.";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}

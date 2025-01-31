# Copyright 2025 TII (SSRC) and the Ghaf contributors
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

      Usage:        ghaf-rebuild <target-ip> <flake-target> [options]

      Options:
        -h, --help  Show this help message

        *           nixos-rebuild options as per https://nixos.wiki/wiki/Nixos-rebuild
                    or nixos-rebuild --help

      Example:      ghaf-rebuild 192.168.0.123 .#lenovo-x1-carbon-gen11-debug switch

    EOF
    }

    if [ $# -le 2 ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
      script_usage
      exit 0
    fi

    if ${ipcalc}/bin/ipcalc -c "$1"; then
      proxy_jump="$1"
    else
      exit 1
    fi

    build_target="$2"
    shift 2

    export NIX_SSHOPTS="-o ProxyJump=root@$proxy_jump"
    nixos-rebuild --flake "$build_target" --target-host root@ghaf-host --fast "$@"
  '';
}

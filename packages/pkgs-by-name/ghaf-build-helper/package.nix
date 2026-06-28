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

      --insecure         Disable SSH host key checking for this invocation.
                         Adds: -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null

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

        NIX_SSHOPTS="-o ProxyJump=root@$proxy_jump"

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
            --insecure)
              NIX_SSHOPTS+=" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
              ;;
            *)
              args+=("$arg")
              ;;
          esac
        done

        export NIX_SSHOPTS

        # Capture the current system path on the target before rebuild for diffing.
        # /nix/var/nix/profiles/system is used (not /run/current-system) so that
        # "boot" rebuilds also have a correct baseline.
        old_system=""
        # shellcheck disable=SC2086
        old_system=$(ssh $NIX_SSHOPTS root@ghaf-host readlink -f /nix/var/nix/profiles/system 2>/dev/null || true)

        show_nvd_diff() {
          local old="$1" new="$2"
          [ -n "$old" ] && [ -n "$new" ] && [ "$old" != "$new" ] || return 0
          # shellcheck disable=SC2086
          ssh $NIX_SSHOPTS root@ghaf-host command -v nvd &>/dev/null || return 0
          echo ""
          echo "--- Package diff ---"
          # shellcheck disable=SC2086,SC2029
          ssh $NIX_SSHOPTS root@ghaf-host nvd diff "$old" "$new" || true
        }

        # Detect whether the requested action is "switch"
        is_switch=false
        upload_args=()

        # Replace "switch" with "boot" so nixos-rebuild sets the profile
        # and bootloader but leaves the running system untouched
        # This lets us show the diff before any service restarts happen
        for arg in "''${args[@]}"; do
          [ "$arg" = "switch" ] && is_switch=true && upload_args+=("boot") && continue
          upload_args+=("$arg")
        done

        if $is_switch; then
          nixos-rebuild --flake "$build_target" --target-host root@ghaf-host --no-reexec "''${upload_args[@]}"

          # shellcheck disable=SC2086
          new_system=$(ssh $NIX_SSHOPTS root@ghaf-host readlink -f /nix/var/nix/profiles/system 2>/dev/null || true)
          show_nvd_diff "$old_system" "$new_system"
          if [ -z "$new_system" ]; then
            echo "Unable to resolve uploaded system profile on target; refusing to queue switch activation" >&2
            exit 1
          fi

          # Activate via systemd-run --no-block so the unit is detached from the
          # SSH session.  The connection may drop once network services restart
          echo ""
          echo "Activating new system (connection may drop)..."
          # shellcheck disable=SC2086,SC2029
          if ! ssh $NIX_SSHOPTS root@ghaf-host \
            "systemd-run --unit=ghaf-rebuild-switch --description='Ghaf rebuild switch activation' --collect --no-block -- $new_system/bin/switch-to-configuration switch"; then
            echo "Failed to queue remote switch activation on target" >&2
            exit 1
          fi
          echo "Remote switch activation queued as ghaf-rebuild-switch.service"
        else
          nixos-rebuild --flake "$build_target" --target-host root@ghaf-host --no-reexec "''${upload_args[@]}"

          # shellcheck disable=SC2086
          new_system=$(ssh $NIX_SSHOPTS root@ghaf-host readlink -f /nix/var/nix/profiles/system 2>/dev/null || true)
          show_nvd_diff "$old_system" "$new_system"
        fi
  '';
  meta = {
    description = "Helper script to use nixos-rebuild without persistent changes of the ssh configuration.";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}

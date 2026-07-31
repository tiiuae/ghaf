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
  # `nixos-rebuild` is only an alias for this now (nixpkgs aliases.nix, "Added
  # 2025-12-02"), so depend on the real package. It still installs a binary called
  # `nixos-rebuild`, which is what the script below invokes.
  nixos-rebuild-ng,
  ipcalc,
}:
writeShellApplication {
  name = "ghaf-build-helper";
  runtimeInputs = [
    nixos-rebuild-ng
    ipcalc
  ];
  text = ''
        function script_usage() {
          cat << EOF

    Usage:   ghaf-rebuild <target-ip|ssh-alias> <flake-target> [nixos-rebuild options]

    The first argument is the net-vm to proxy-jump through. Prefer an ssh_config
    host alias over a bare IP: ssh matches Host blocks on the name as written, so
    an IP picks up no IdentityFile and falls back to your default keys.

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
      ghaf-rebuild ghaf-usb .#intel-laptop-debug switch
      ghaf-rebuild ghaf-usb .#intel-laptop-debug --force-local switch
      ghaf-rebuild 192.168.0.123 .#intel-laptop-debug switch

    EOF
        }

        if [ $# -le 2 ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
          script_usage
          exit 0
        fi

        proxy_jump="$1"
        # Accept either a bare IP or an ssh_config host alias.
        #
        # ssh matches Host blocks against the name as written on the command
        # line, never the resolved address, so "root@192.168.0.123" matches only
        # "Host *" -- and an alias carrying IdentityFile/User for this device is
        # silently bypassed. On a workstation whose default identities are
        # FIDO2/YubiKey-backed that means the jump hop asks for a touch, or fails
        # outright, while the second hop (root@ghaf-host, an alias) works fine.
        # Passing the alias instead lets its own IdentityFile and User apply.
        if ipcalc -c "$proxy_jump" >/dev/null 2>&1; then
          jump_host="root@$proxy_jump"
        else
          # An alias supplies its own User; do not force root@ over it.
          jump_host="$proxy_jump"
          if [ "$(ssh -G "$proxy_jump" | awk '/^hostname /{print $2; exit}')" = "$proxy_jump" ]; then
            echo "Not an IP address, and no 'Host $proxy_jump' block in your ssh config: $proxy_jump" >&2
            exit 1
          fi
        fi
        build_target="$2"
        shift 2

        NIX_SSHOPTS="-o ProxyJump=$jump_host"

        # Parse flags
        insecure=false
        args=()
        for arg in "$@"; do
          case "$arg" in
            --force-remote)
              args+=(--max-jobs 0)
              ;;
            --force-local)
              args+=(--builders "")
              ;;
            --insecure)
              insecure=true
              ;;
            *)
              args+=("$arg")
              ;;
          esac
        done

        if $insecure; then
          # ProxyJump spawns a separate ssh process that does not inherit -o options,
          # so StrictHostKeyChecking=no would not apply to the jump host. Use a temp
          # config with ProxyCommand instead so both hops skip host key checking.
          _ssh_cfg=$(mktemp)
          printf 'Host ghaf-host\n\tStrictHostKeyChecking no\n\tUserKnownHostsFile /dev/null\n\tProxyCommand ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %%h:%%p %s\n' "$jump_host" > "$_ssh_cfg"
          # shellcheck disable=SC2064
          trap "rm -f $_ssh_cfg" EXIT
          NIX_SSHOPTS="-F $_ssh_cfg"
        fi

        export NIX_SSHOPTS

        # Capture the current system path on the target before rebuild for diffing.
        # /nix/var/nix/profiles/system is used (not /run/current-system) so that
        # "boot" rebuilds also have a correct baseline.
        old_system=""
        # shellcheck disable=SC2086
        old_system=$(ssh $NIX_SSHOPTS root@ghaf-host readlink -f /nix/var/nix/profiles/system 2>/dev/null || true)

        # The diff runs on the target, because that is where both closures exist. dix is
        # shipped by the debug profile (modules/development/debug-tools.nix); a release
        # image, or one flashed before dix replaced nvd, will not have it.
        show_system_diff() {
          local old="$1" new="$2"
          [ -n "$old" ] && [ -n "$new" ] && [ "$old" != "$new" ] || return 0
          # shellcheck disable=SC2086
          if ! ssh $NIX_SSHOPTS root@ghaf-host command -v dix &>/dev/null; then
            # Say so rather than returning quietly: otherwise a missing tool is
            # indistinguishable from "nothing changed".
            echo ""
            echo "(package diff skipped: dix is not on the target)"
            return 0
          fi
          echo ""
          echo "--- Package diff ---"
          # shellcheck disable=SC2086,SC2029
          ssh $NIX_SSHOPTS root@ghaf-host dix "$old" "$new" || true
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
          show_system_diff "$old_system" "$new_system"

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
          show_system_diff "$old_system" "$new_system"
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

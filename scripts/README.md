<!--
SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Scripts

This directory contains scripts for maintaining the documentation dependencies,
developing Ghaf, and preparing NixOS flash runtimes.

## Files

- `port.sh`: Builds a Ghaf flash derivation and copies its runtime closure to a
  local directory, remote SSH destination, or compressed tar archive.
- `launcher.sh`: Mounts a copied runtime and runs `flash-ghaf-host`. For an
  adjacent `.tar.gz` or `.tgz` archive, it extracts the runtime to a temporary
  directory and removes it when the command exits.
- `update-npm-deps-hash.sh`: Automatically updates the `npmDepsHash` in
  `/docs/default.nix` when Dependabot updates the documentation dependencies.
- `test-update-npm-deps-hash.sh`: Validates the npm dependency hash update
  functionality.
- `dev-container.sh`, `dev-vm.sh`, and `ubuntu-setup.sh`: Development setup
  helpers.

## Exporting a flash runtime

Run `port.sh` from the Ghaf Support repository root so Nix uses this project's
flake. By default, it builds
`#nvidia-jetson-orin-nx-debug-from-x86_64-flash-qspi` and includes the Bash,
coreutils, and util-linux runtime closures.

```bash
# Copy the runtime to a local directory
./scripts/port.sh /mnt/flash-runtime

# Copy to a remote Linux host (SSH and remote rsync required)
./scripts/port.sh user@host:/srv/flash-runtime

# Create a gzip-compressed archive and place launcher.sh beside it
./scripts/port.sh -tar /mnt/usb/flash-runtime.tar.gz

# Select another flake attribute
./scripts/port.sh /mnt/flash-runtime '#nixosConfigurations.host.config.system.build.toplevel'
```

Local directory mode uses `sudo` to create and populate the destination. Tar
mode stages the runtime under a temporary directory and does not need `sudo`.
For tar mode, the destination is an archive file path; `.tar` is changed to
`.tar.gz`, and destinations without an archive suffix get `.tar.gz` appended.
The launcher is placed in the archive's directory. Set `LAUNCHER_URL` to use a
launcher other than the copy alongside `port.sh`.

## Running the flash runtime

For a directory runtime, pass its root or set `RUNTIME_ROOT`:

```bash
./scripts/launcher.sh --runtime-root=/mnt/flash-runtime
./scripts/launcher.sh --runtime-root /mnt/flash-runtime --debug -- --flash-option value
```

When `launcher.sh` is beside a single `.tar.gz` or `.tgz` archive, run it
without `--runtime-root`; it extracts and cleans up the runtime automatically:

```bash
cd /mnt/usb
./launcher.sh --debug -- --flash-option value
```

The target Linux system needs `sudo` and mount support. The launcher uses a
private mount namespace when `unshare` is available and otherwise temporarily
bind-mounts the runtime at `/nix`.

## NPM Dependencies Hash Automation

When Dependabot creates a PR to update npm dependencies in `/docs/package.json`
or `/docs/package-lock.json`, the GitHub workflow
`.github/workflows/update-npm-deps-hash.yml` automatically:

1. Detects the Dependabot PR.
2. Runs the update script, which attempts to build the documentation, extracts
   the correct hash from the Nix build error, updates `/docs/default.nix`, and
   verifies the build with the new hash.
3. Commits and pushes the updated `default.nix` to the same PR.

## Testing

Run the test script to validate functionality:

```bash
./scripts/test-update-npm-deps-hash.sh
```

This tests:

- Hash extraction from various Nix error message formats
- File structure validation
- Sed replacement functionality
- Script permissions

## Manual Usage

The script can also be run manually when needed:

```bash
./scripts/update-npm-deps-hash.sh
```

Note: This requires Nix to be installed and the script will attempt to build the documentation package to determine the correct hash.

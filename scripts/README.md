# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Scripts

This directory contains maintenance and development helpers, plus the launcher
used by the Nix-built Orin flash runtime artifact.

## Orin flash runtime artifact

The flash runtime is built as a Nix output alongside the Orin flash-script
packages. The runtime package contains a compressed copy of the exact flasher
closure, a recorded path to that flasher, and the launcher version from the
same source revision. It does not rebuild or discover a flasher closure at
release time.

For example, build the NX debug runtime on x86_64:

```bash
nix build .#nvidia-jetson-orin-nx-debug-from-x86_64-flash-runtime
```

The result directory contains `flash-runtime.tar.gz` and `launcher.sh`. Keep
both files together when publishing or downloading the artifact. Run
`./result/launcher.sh` to extract the adjacent archive into a temporary
runtime and start the bundled flasher. The Linux host needs `bash`, `tar`,
`gzip`, `sudo`, and mount support.

The artifact is a regular Nix package output and can be selected by release
jobs for publication to the project's artifact or OCI storage. The flasher and
launcher are pinned together by the Nix derivation, so release testing and
customer downloads can use the same build result.

`port.sh` remains as a convenience wrapper for building this Nix output and
copying the resulting archive and launcher to a local directory. It no longer
copies or assembles Nix store closures itself.

## Other scripts

- `update-npm-deps-hash.sh`: Automatically updates the `npmDepsHash` in
  `/docs/default.nix` when Dependabot updates the documentation dependencies.
- `test-update-npm-deps-hash.sh`: Validates the npm dependency hash update
  functionality.
- `dev-container.sh`, `dev-vm.sh`, and `ubuntu-setup.sh`: Development setup
  helpers.

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

Run the test script to validate the npm dependency hash automation:

```bash
./scripts/test-update-npm-deps-hash.sh
```

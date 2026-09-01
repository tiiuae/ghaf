<!--
SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: Apache-2.0
-->

# Ghaf — instructions for coding agents

Ghaf is a Nix/NixOS security framework that compartmentalises a device into a host plus a
fleet of microVMs, with inter-VM communication over GIVC. Targets are x86_64 and aarch64.

This file is the shared instruction set for every agent working in this repo. Detailed
procedures live in skills (see [Where the depth is](#where-the-depth-is)); keep this file
short and limited to things that are true for all work.

## Before you commit

These are enforced by CI, so a change that skips them will fail there instead of here:

```bash
nix fmt -- --fail-on-change          # treefmt: nixfmt-rfc-style, ruff, shellcheck, prettier
nix develop --command reuse lint     # every file needs SPDX copyright + licence
nix flake check                      # full validation
```

New files need an SPDX header — Apache-2.0 for code, CC-BY-SA-4.0 for documentation:

```nix
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
```

If a file cannot carry a header (YAML frontmatter must come first, binary assets), add it
to the annotations block in `REUSE.toml` instead.

Commit subjects follow conventional commits: `feat:`, `fix:`, `chore:`, `docs:`,
`refactor:`, `test:`, with an optional scope — `fix(vm): resolve networking in gui-vm`.
Do not commit or push unless you were asked to.

## Layout

- `modules/` — NixOS modules: `common/`, `hardware/`, `desktop/`, `microvm/`, `givc/`,
  `development/`, `reference/`, `profiles/`, `partitioning/`
- `targets/laptop/machines.nix` — the x86 machine table. **Data only**, enforced by
  `checks.laptop-table-is-data`. An Intel laptop needs no stanza at all -- it boots the generic
  `intel-laptop` image. Only a board that image cannot describe (AMD, desktop, discrete GPU)
  gets one stanza here plus a module under `modules/reference/hardware/`; everything a machine
  needs (ACS ids, suspend mode, VM memory) goes in that module, never in the table.
  `targets/laptop/axes.nix` holds the feature axes
  (`low-mem`, `minimal-mem`, `storeDisk`), expanded as a power set — never write out the
  combinations. Axes sharing a `group` (the two memory ones) are mutually exclusive.
- `targets/` — target definitions (`laptop`, `vm`, `generic-x86_64`, `nvidia-jetson-orin`, …)
- `packages/pkgs-by-name/<package-name>/package.nix` — flat, no first-letter sharding
- `overlays/`, `lib/`, `nix/`, `tests/`, `docs/`

New modules go to `modules/<category>/<name>.nix`, or a directory with `default.nix` when
they grow. File names are kebab-case; option names are camelCase under a `ghaf.` prefix:

```nix
{ config, lib, pkgs, ... }:
let cfg = config.ghaf.<module-name>;
in {
  options.ghaf.<module-name>.enable = lib.mkEnableOption "<feature>";
  config = lib.mkIf cfg.enable { };
}
```

## Everyday commands

| Task | Command | Depth |
|---|---|---|
| See what a build will cost | `nix build --dry-run .#<target>` | `ghaf-build` |
| Build an image | `nix build .#intel-laptop-debug` | `ghaf-build` |
| Build many targets | `nix-fast-build --flake '.#packages.x86_64-linux' --select …` | `ghaf-build` |
| Deploy without reflashing | `nix develop --command ghaf-rebuild <netvm-ip> .#<target> boot`, then reboot | `ghaf-deploy` |
| Flash an image | `sudo nix develop --command ghaf-flash -d /dev/sdX -i result/ghaf-image.raw.zst` | `ghaf-deploy` |
| Reach a device or VM | `ssh ghaf@<host_ip>`, then `ssh <vm>` from there | `ghaf-connect` |
| Collect logs across VMs | `.claude/skills/ghaf-logs/scripts/collect-logs.sh --machine <name>` | `ghaf-logs` |
| Run hardware tests | `.github/skills/ghaf-hw-test/ghaf-hw-test test --device <name> --ip <IP>` | `ghaf-test` |

Device details (addresses, drives, serial nodes, target and test names per machine) live in
`.github/skills/ghaf-hw-test/config.yaml`, with per-machine values (addresses, MACs, ssh
identities, drive nodes) in the gitignored `config.local.yaml` beside it. Read them rather than
asking or guessing; if a field is null in both, ask once and offer to write it to the local file.

## Things that bite

- **x86 laptops share one generic image**: `intel-laptop-debug`. There are no per-machine
  laptop targets any more. Only non-Intel boards keep their own: `lenovo-t14-amd-gen5`,
  `alienware-m18-R2`, `demo-tower-mk1`, `tower-5080`. A new Intel laptop needs no target --
  at most a quirk added to an existing union list (ACS ids, `s2idleModels`, `known-devices.nix`).
- **Jetson targets must be named `-from-x86_64` on an x86 build host.** The native aarch64
  attributes are not in `packages.x86_64-linux`, so the plain name resolves to nothing.
- **JetPack-only packages cannot use `packages/pkgs-by-name/`.** That directory and
  `packages/own-pkgs-overlay.nix` expose packages for every system, while the JetPack overlay
  is applied only inside Jetson configurations. Use a relative-path `callPackage` from a
  JetPack-configured module to avoid breaking x86_64 evaluation.
- **The image you flash is always `result/ghaf-image.raw.zst`** (plus `ghaf-image.bmap`,
  used automatically). No target emits `result/<target>.img` any more.
- **The test suite names the physical machine, not the image**: `robot-test -d` takes
  `darter-pro`, `lenovo-x1`, `dell-7330`, `orin-agx`, … A wrong value does not error, it
  silently runs a different subset of tests.
- **Flakes ignore untracked files.** A new file is invisible to `nix build` until at least
  `git add -N`.
- **`nixos-rebuild switch` cannot repartition, rewrite a bootloader, or change the kernel
  cmdline.** Those need a reflash, and switching anyway leaves a device that disagrees with
  your source tree.
- **A host switch does not restart the microVMs.** They keep their old configuration until
  `systemctl restart microvm@<vm>.service`. This is why `boot` + reboot is the default
  deploy path: the reboot restarts every VM, so a guest change cannot be left unapplied
  while the host reports success.

## Where the depth is

- `.claude/skills/ghaf-*/SKILL.md` — build, deploy, connect, logs, test, and the full
  development loop. Claude Code loads these automatically; other agents should read them as
  documentation when the task matches.
- `.github/skills/ghaf-hw-test/` — the hardware test CLI, discovered by Copilot CLI.
- `docs/src/content/docs/ghaf/` — user and developer documentation (Astro Starlight).

## Related repositories

- [ghafpkgs](https://github.com/tiiuae/ghafpkgs) — Ghaf-specific packages
- [ghaf-infra](https://github.com/tiiuae/ghaf-infra) — CI/CD infrastructure
- [ci-test-automation](https://github.com/tiiuae/ci-test-automation) — the Robot Framework suite

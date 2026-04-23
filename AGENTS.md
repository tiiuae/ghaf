<!--
    SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# AGENTS Guide

This file is the operational guide for AI coding agents working in the Ghaf repository.

## Purpose

- Ship correct, minimal, reviewable changes that follow Ghaf architecture and policy
- Prefer existing patterns over invention, especially in modules, targets, and flake exports
- Keep security, licensing, and reproducibility constraints intact

## Source Priority

When instructions conflict, follow this priority order:

1. Current task prompt from the user
2. Repository code and CI workflows (actual behavior)
3. `CONTRIBUTING.md`, `README.md`, `SECURITY.md`, PR template
4. Additional guidance docs under `docs/` and `.github/`

If documentation conflicts with code or workflows, follow code and note the mismatch in your response.

## Repository Map

- `flake.nix`: top-level inputs, systems, and imported flake modules
- `nix/`: devshell, treefmt, pre-commit hook wiring, and shared Nix settings
- `modules/`: NixOS modules (`common`, `hardware`, `microvm`, `profiles`, `reference`, and others)
- `targets/`: exported hardware and VM targets, plus cross-build variants
- `packages/`: custom packages and overlays, mostly under `pkgs-by-name`
- `lib/`: reusable library code, including global config and builder APIs
- `tests/`: flake checks and test packages
- `docs/`: Starlight/Astro documentation source
- `.github/workflows/`: CI truth source for checks, eval, build, docs deploy

## Standard Agent Workflow

1. Inspect the relevant target/module/package paths before editing
2. Make the smallest coherent change that matches local patterns
3. Run the narrowest meaningful validation for the touched area
4. Report what changed, what was validated, and what was not validated

Do not refactor unrelated areas in the same change unless requested.

## Change Routing

Use these rules to place changes correctly:

- New or changed host or VM behavior: `modules/`
- Device-specific behavior: `modules/reference/hardware/` and `targets/`
- New exported build target or variant: `targets/*/flake-module.nix`
- Ghaf package additions: `packages/pkgs-by-name/*` and package overlay wiring
- Shared build/config plumbing: `nix/`, `lib/`, `flake.nix`
- Documentation pages/navigation: `docs/src/content/docs/` and `docs/astro.config.mjs`

## Nix Module Conventions

- Add SPDX headers to new files
- Keep options under `ghaf.*` namespace unless extending external module options intentionally
- Use `lib.mkEnableOption` for feature flags
- Use typed `lib.mkOption` with clear descriptions
- Use `lib.mkIf` for conditional config
- Prefer `lib.mkDefault` for overridable defaults; avoid `lib.mkForce` unless required
- Include `_file = ./<filename>.nix;` in Nix modules for better evaluation traces
- Reuse `globalConfig` and `hostConfig` patterns already used by VM/base composition

## Build and Validation Matrix

Select checks by scope. Run the smallest set that can catch regressions in your change.

- Docs only:
  - `nix build .#doc`
- Nix/module/target/package changes (minimum):
  - `nix fmt -- --fail-on-change`
  - `nix develop --command reuse lint`
- Broader evaluation confidence:
  - `nix flake show --all-systems --accept-flake-config`
  - `make-checks` (if available in devshell)
- CI-parity checks for pre-commit hooks:
  - `nix build .#checks.x86_64-linux.pre-commit`

For long builds or hardware-dependent paths, state clearly if validation was not run locally.

## Commit and PR Policy

Follow Linux-kernel-style commit message structure (project policy):

- Subject line in imperative mood, concise, no trailing period
- Optional body explains what and why, wrapped for readability
- Keep commits logically scoped

PRs should include:

- Clear change description and rationale
- Explicit verification steps
- Any skipped checks and why

## Security and Safety Guardrails

- Never commit secrets, credentials, tokens, private keys, or local machine paths
- Treat flashing operations as destructive
  - Never guess block devices
  - Require explicit device path from user context before flash commands
- Be careful around secure boot key material under `modules/secureboot/keys/`
- Prefer reversible, auditable edits over broad rewrites

## Documentation and Style Expectations

- Keep docs in plain US English and active voice
- Use title case for headings
- Keep instructions explicit and step-based for operational tasks
- Update docs when behavior changes

## Known Drift to Watch

- Some documentation pages may lag behind current code exports or script paths
- If you find stale references, align implementation-first and include docs fixes in the same change when practical

## Agent Output Expectations

- Be explicit about files touched and why
- Distinguish facts from assumptions
- Call out risk, impact, and validation status
- Offer next concrete steps only when useful

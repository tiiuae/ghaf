---
name: ghaf-build
description: Build Ghaf images and configurations - picking the right target name, checking the binary cache before committing to a long build, building many targets with nix-fast-build, and reading Ghaf's common eval failures. Use whenever asked to build a Ghaf image or target, to check whether something still builds or evaluates, to build for a laptop or Jetson, or before deploying a change to a device. Also use when a nix build or eval fails in this repo and the error needs interpreting.
---

# Building Ghaf

Most of the cost here is choosing correctly before you start: the wrong target name wastes
an hour, and a target that isn't cached is a very different proposition from one that is.

## Pick the target

x86 laptops share the generic image. `intel-laptop-debug` is the default path —
`modules/reference/hardware/intel-laptop/` passes display, network and audio through by PCI
class wildcard rather than per-device IDs, so it covers the fleet. Per-machine targets
(`lenovo-x1-carbon-gen11-debug`, `system76-darp11-b-debug`, …) still exist for special
cases but are no longer where you start.

Naming follows `<name>-{debug,release}[-installer]`, with variants like `-low-mem`,
`-storeDisk`, `-sysupdate`. `debug` is what you want for development: it enables the ssh
daemon and default accounts that every other skill here depends on.

**Jetson targets must be named `-from-x86_64` from an x86 build host.** The native aarch64
attributes are not exposed in `packages.x86_64-linux`, so naming them resolves to nothing —
this is a real trap that has already cost time in this repo's own tooling. Same for
`-flash-script`: `nvidia-jetson-orin-agx-debug-from-x86_64-flash-script`.

The device config records the right target per machine:

```bash
nix-shell .github/skills/ghaf-hw-test/shell.nix --run \
  'python3 -c "import yaml;print(yaml.safe_load(open(\".github/skills/ghaf-hw-test/config.yaml\"))[\"devices\"][\"darter-pro\"][\"ghaf_target\"])"'
```

To confirm a name exists before spending anything on it:

```bash
nix eval .#packages.x86_64-linux --apply \
  'ps: builtins.elem "intel-laptop-debug" (builtins.attrNames ps)'
```

## Find out what you are committing to

A cached target is minutes; the same target from source is one to three hours. Always look
before starting a long build:

```bash
nix build --dry-run .#intel-laptop-debug
```

Read the two lists it prints: "will be fetched" is cheap, "will be built" is not. A handful
of derivations to build is normal after a config change; hundreds means you have moved
something deep — a kernel option, an overlay applied globally, a bumped input — and it is
worth checking that was intentional before letting it run.

Ghaf's cache is `https://ghaf-dev.cachix.org`, and CI only populates it for pushed commits,
so anything unique to your working tree will always build locally.

## Build one target

```bash
nix build .#intel-laptop-debug --option builders ''      # keep it local
nix build .#intel-laptop-debug -L                        # stream build logs
```

`--option builders ''` forces everything onto this machine. Use it when you want
predictability or the remote builders are unavailable; drop it when you want the aarch64
builder to do the aarch64 work.

## Build many targets

`nix-fast-build` evaluates and builds a whole attribute set, and `--select` filters it
before evaluation so excluded targets cost nothing:

```bash
# every x86 target except the nvidia/nxp cross builds
nix-fast-build --flake '.#packages.x86_64-linux' \
  --select 'ps: builtins.removeAttrs ps (builtins.filter (n: builtins.match ".*(nvidia|nxp).*" n != null) (builtins.attrNames ps))' \
  --skip-cached --no-link -j 4

# only the nvidia targets, images without the flash helpers
nix-fast-build --flake '.#packages.x86_64-linux' \
  --select 'ps: builtins.removeAttrs ps (builtins.filter (n: builtins.match ".*nvidia.*" n == null || builtins.match ".*-(flash-qspi|flash-script|ghafImage)" n != null) (builtins.attrNames ps))' \
  --skip-cached --no-link --option builders '' -j 2
```

For native aarch64 attributes, `--systems aarch64-linux` is mandatory and its absence fails
*silently*: `--systems` defaults to the host system, and jobs whose system doesn't match are
dropped without a warning, so you get a full evaluation followed by zero builds and a clean
exit. Those builds want a real aarch64 builder — do not pass `--option builders ''` there
or they land on local qemu emulation.

## What the build produces

Every image target emits the same names, from `modules/partitioning/disko-debug-partition.nix`:

```
result/ghaf-image.raw.zst    the compressed image
result/ghaf-image.bmap       block map, used automatically when flashing
```

Older docs still mention `result/ghaf-<target>.img`; no target produces that any more.

## Reading Ghaf's eval failures

- **`option '…' was accessed but has no value defined`** — usually a nixpkgs bump changed a
  module's shape underneath ghaf's overrides. Setting a sub-attribute of a rule that
  upstream no longer defines *creates* a half-built rule. Find who last defined it upstream
  before patching around it.
- **IFD errors** — `allow-import-from-derivation = false` is set here on purpose. Fix the
  expression; do not enable IFD to get past it.
- **`Path '…' in the repository is not tracked by Git`** — flakes ignore untracked files.
  `git add -N <path>` makes a new file visible without staging its content.
- **A dirty tree changes the flake source hash**, so anything embedding it (notably the
  docs, which bake store paths into the options JSON) rebuilds on every change. That is
  expected, not a fault.

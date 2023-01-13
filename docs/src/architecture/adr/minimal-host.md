# Minimal host

## Status

Proposed

## Context

Ghaf uses the default NixOS configuration as a baseline to build the target image.

The default NixOS configuration is targeted for more general use with the inclusion of
multiple packages that are not supporting the Ghaf design target of a minimal trusted
computing base (TCB) to protect the host.

This structure in the Ghaf host configuration imports the NixOS minimal profile
which suits the minimal TCB better. Even better, the modular declarative profile enables
the further optimization of the minimal TCB while supporting other profiles that suit
evaluation of other objectives such as feasibility studies of additional functionality,
security and performance.

## Decision

This change adopts a minimal profile from NixOS. It reduces both image and root partition
size by eliminating the host OS content as defined in the NixOS minimal profile.

The proposed profile from NixOS can be [reviewed here](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/profiles/minimal.nix).

## Consequences

Additional host dependencies must be declared explicitly to get included on the host.

Some functionality assumed with the default host may break or may not be available as
the earlier baseline functionality with graphics and other functionality has not yet
been implemented. In practice, the host will not have graphical libraries by default, and
such functionality would need to be either imported using another profile or passed
through to a guest VM that supports modular design by separating the graphics architecture
from the host. The same applies to other guest VMs that implement other system functionality.

Further development of the host security, such as hardening, becomes easier as such
profiles can be tested in isolation.

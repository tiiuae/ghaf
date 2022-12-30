# Basic Security Measures

## Source Code / Version Control Security

The source code security is based on the fact that the source code is two-person reviewed, version controlled, and the history is verified and retained indefinitely.

### Commit Signing
All the commits to repositories must be GPG-signed. This can be achieved by enabling GPG commit signatures in the config:

`git config --global commit.gpgsign true`

For more detailed information, see the [Signing commits](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits "Signing Commits on GitHub") article of the GitHub Docs.

### Branch Protection
In the case of GitHub the following settings should be considered:

  + Require pull request reviews before merging (req: two-person reviewed source).
  + Require status checks before merging.
  + Require conversation resolution before merging.
  + Require signed commits.
  + Deletions should be forbidden (req: immutable history).

## Software Signing

Software signing is an important measure to validate the author and ensure that the code has not been altered on the way from the developer to the customer. Nix tooling is offering means to sign the derivations using libsodium with EdDSA, however, as the modular system is assumed, scripts need to be developed to support signing mechanisms in an absence of Nix tooling.

By default, the software image is signed only at the binary cache per request. Which leaves the path from Hydra to the binary cache unsecured. The problem can be resolved in two ways:

  + Enabling the image signing on Hydra
  + Shared Nix Store

The option with shared Nix store is rather straightforward.

Enabling the image signing on Hydra requires some extra work due to the lack of support of image signing at Hydra at the time of writing this document. As already mentioned, NixOS is using libsodium-based EdDSA solution for image signing. So similar scripts can be implemented. For example, in Python by using existing libsodium bindings, such as PyNaCl.

## Data Encryption in Transit

All the data should be transported over secure encrypted channels. Since all the transportation is done over TCP/IP protocol stack, it is possible to use native solutions like TLS to secure the traffic between the nodes. Version 1.2 is a minimum requirement.

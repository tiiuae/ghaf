# Basic Security Measures

## Source code / Version control security

Briefly, the source code security is based on the fact that the source code is Two-person reviewed, version controlled, the history is verified, retained indefinitely. 

### Commit signing
All the commits to repositories must be GPG-signed. This can be achieved by enabling GPG commit signatures in the config:

git config --global commit.gpgsign true

More detailed information for GitHub is available on: Signing commits - GitHub Docs 

### Branch protection
In case of GitHub the following settings should be considered:

  + Require pull request reviews before merging (req: Two-person reviewed source)
  + Require status checks before merging
  + Require conversation resolution before merging
  + Require signed commits (see commit signing)
  + Deletions should be forbidden (req: immutable history)

## Software Signing

Software signing is an important measure to validate the author and ensure that the code has not been altered on the way from the developer to the customer. Nix tooling is offering means to sign the derivations using libsodium with EdDSA, however, as the modular system is assumed, scripts need to be developed to support signing mechanisms in an absence of Nix tooling.

As of today, the software image is singed only on the binary cache per request. Which means that it is possible to request a software signature separately as part of nar-info. 

At the same time, the code is not signed on the way from repository to Hydra and from Hydra to binary cache, leaving those parts insecure.

## Data encryption in transit

All the data should be transported over secure encrypted channels. Since all the transportation is done over TCP/IP protocol stack, it is possible to use native solutions like TLS to secure the traffic between the nodes. Version 1.2 is a minimum requirement.

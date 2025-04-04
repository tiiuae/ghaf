<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Public Key Infrastructure

In the SCS context, a public key infrastructure (PKI) term refers to a system for the creation, storage, and distribution of digital certificates which are used to verify that a particular key belongs to a certain entity. PKI creates and manages a hierarchical set of digital certificates which map public keys to certain entities. Storage and revocation methodologies are to be defined.

The PKI of SCS should consist of:
  + Certificate authority (CA) for storing, issuing, and signing the digital certificates.
  + Registration authority (RA) for requesting entity identity verification.
  + Central directory for the secure storage of the keys.
  + Certificate Management System (CMS) for managing access to stored certificates.


## Private Certificate Authority (PCA)

PCA enables the creation of private certificate authority hierarchies, consisting of Root and Subordinate CAs. It issues end-entity X.509 certificates, that are used for: 

  + Encrypted TLS communication channels (data encryption in transit)
  + Code and image signing

PCA can be established in the cloud or on-premises. Initially, the OpenSSL-based solution deployed on-premises is assumed, however, some of the target projects might consider using commercial cloud solutions. 


## Hardware Security Module

On-premises solution can be further improved by adding a Hardware Security Module (HSM). It is a physical device for managing cryptographic material such as digital keys. 

HSM can be also used to perform cryptographic operations such as digital signing, encryption, and decryption. The HSM contains one or more Secure Cryptoprocessors that are dedicated microprocessors optimized for carrying out cryptographic operations. 

## CA Hierarchy Options

CA usually consists of:
  + Root CA - the root of trust of the entire PKI, for issuing and signing the certificates used by other CAs.
  + Subordinate CA for issuing end-entity certificates.

There are three types of hierarchies: one-tier, two-tier, and three-tier. The hierarchy can be chosen based on the target project's needs and complexity. A one-tier hierarchy is not considered for any production usage due to the low security, as the compromise of a single CA leads to a compromise of the entire PKI.

In a two-tier hierarchy, the Root CA and issuing (Subordinate) CAs are separated for increasing the security level. This is the simplest production level hierarchy allowing to keep Root CA at the most secure and restrictive levels, yet making subordinate CA access slightly more permissive. This hierarchy is most likely sufficient for most of the target projects.

In a three-tier CA, an intermediate CA is placed between the Root CA and the Subordinate (issuing) CA. This is done to separate the Root CA from low-level CA operations. The middle layer (intermediate CA) is only used to sign Subordinate CAs that issue the end-entity certificates. 


## Proposed CA Hierarchy

The following diagram describes the proposed CA for the SCS. The three-tier CA is chosen based on the high-security level and the potential need to scale it to several projects, later on, keeping the main control under the same Root CA.

![Proposed CA](../img/ca_implementation.drawio.png "CA Implementation Proposal")

# Public Key Infrastructure

In SCS context a public key infrastructure (PKI) term refers to a system for creation, storage, and distribution of digital certificates which are used to verify that a particular key belongs to a certain entity. PKI is creating and managing a hierarchical set of digital certificates which map public keys to certain entities. Storage and revocation methodologies are to be defined.

The PK of SCS should consist of:
  + A certificate authority (CA) responsible for storing, issuing and signing the digital certificates
  + A registration authority (RA) responsible for requesting entity identity verification
  + A central directory responsible for secure storage of the keys
  + A Certificate Management System (CMS) managing access to stored certificates
 
## Private Certificate Authority (PCA)

PCA enables creation of private certificate authority hierarchies, consisting of root and subordinate CAs. It issues end-entity X.509 certificates, that are used for: 

  + Encrypted TLS communication channels (data encryption in transit)
  + Code and image signing

PCA can be established in the cloud or on premise. Initially, openssl based on-prem solution is assumed, however, some of the target projects might consider using commercial cloud solutions.

### CA Hierarchy Options

CA usually consists of:
  + A Root CA - the root of trust of the entire PKI, responsible for issuing and signing the certificates used by other CAs
  + A Subordinate CA is typically responsible for issuing end-entity certificates

Typically, there are three types of hierarchies. One-tier, two-tier and three-tier. The hierarchy can be chosen based on the target projects needs and complexity, however it is important to keep in mind that one-tier hierarchy is not recommended for any production use due to the low security, as the compromise of a single CA leads to a compromise of the entire PKI, thus one-tier CA hierarchy is not considered in this document.

In a two-tier hierarchy the root CA and issuing (Subordinate) CAs are separated, thus increasing the security level. This is the simplest production level hierarchy allowing to keep root CA at the most secure and restrictive levels, yet making subordinate access slightly more permissive. This hierarchy is most likely sufficient for most of the target projects.

In a three-tier CA an intermediate CA is placed between root CA and Subordinate (issuing) CA. This is done to further separate the root CA from low-level CA operations. The middle layer (intermediate CA) is only used to sign subordinate CAs that issue the end-entity certificates. 


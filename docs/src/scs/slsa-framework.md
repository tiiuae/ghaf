<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# SLSA Framework

Supply chain Levels for Software Artifacts (SLSA) is a security framework for tampering prevention, integrity improvement, and securing packages and infrastructure of a project. For more information about the SLSA framework, see the offical website <https://slsa.dev>.


## SLSA Terminology

**Immutable reference:** An identifier, guaranteed to always point to the same, immutable artifact.

**Provenance:** Metadata about how an artifact was produced.

**Revision:** An immutable, coherent state of a source.


## Levels of Assurance

One of the requirements for the solution is to reach SLSA version 1.0 Level 3 and even go beyond that. This requires a lot of process changes as well as technical work. 

The SLSA version 1.0 model consists of 3 levels, offering an incremental level of anti-tampering protection. There are new versions of SLSA model coming because it is constantly evolving, see <https://slsa.dev/current-activities>.

**Level 0** means no SLSA compliance and no guarantees are given.

**Level 1** Package has provenance showing how it was built. Can be used to prevent mistakes but is trivial to bypass or forge.

**Level 2** Forging the provenance or evading verification requires an explicit “attack”, though this may be easy to perform. Deters unsophisticated adversaries or those who face legal or financial risk.

In practice, this means that builds run on a hosted platform that generates and signs the provenance.

**Level 3** Forging the provenance or evading verification requires exploiting a vulnerability that is beyond the capabilities of most adversaries.

In practice, this means that builds run on a hardened build platform that offers strong tamper protection.

SLSA level is not transitive, thus level of the artifact is not dependent on the level of dependencies, which are expected to have their own SLSA levels. This makes it possible to build a Level 3 artifact from Level 0 dependencies. 

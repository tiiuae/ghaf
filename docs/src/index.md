# TII SSRC Secure Technologies: Ghaf Framework

_[Ghaf](./appendices/glossary.md#ghaf) Framework_ is an open-source project that provides information about our work and studies in the security technologies field in the context of embedded virtualization.

The applied software research supports _[Secure Systems Research Center](./appendices/glossary.md#ssrc)_ focus areas.

## Embedded Virtualization

Embedded virtualization builds on cloud technologies in the development of end-to-end security. With hardware support for virtualization, we provide a hardened system of a small _[trusted computing base (TCB)](./appendices/glossary.md#tcb)_ — thin host — that enables isolation of use cases and their resources. Use cases are protected in guest virtual machines (VMs). Embedded targets are small devices (personal or headless) instead of high-performance cloud servers. Our scope is illustrated in the following diagram.

![Scope!](img/overview.png "Embedded Virtualization Scope")

## Reference Implementation

Ghaf is developing a reference implementation for NVIDIA Jetson devices. See [build instructions](https://github.com/tiiuae/ghaf/#build-instructions) for more info.
Legacy reference implementation for NXP i.MX8 [is available here](https://github.com/tiiuae/spectrum-config-imx8).

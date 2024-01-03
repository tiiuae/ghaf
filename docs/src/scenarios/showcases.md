<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Showcases

The Ghaf Platform can be used in various different environments, configurations, and hardware to serve several purposes. Ghaf is not a fully-fledged product but a module that can serve as a centerpiece to enable secure edge systems.

### Secure Laptop

Secure Laptop demonstrates how our open-source Ghaf Platform can increase the security offering for laptops through hardware-backed isolation by means of virtualization. We use Lenovo ThinkPad X1 Carbon Gen 11 as a target device.

In this showcase, the following applications are running in isolated VMs:

* [Windows VM](./run_win_vm.md)
* Browser VM that can be used as an application launcher. For example, MS Office suite running in the Browser environment. All data is stored in the enterprise cloud.
* PDF Viewer VM. No data can be extracted or shared locally.
* [Cloud Android VM](./run_cuttlefish.md) for secure communication.

Each VM operates independently and securely within its own isolated environment, without interference from other VMs running on the same physical hardware. Additionally beneath the surface Ghaf contains two hidden system VMS:

* [Networking VM](../architecture/adr/netvm.md)
* [GUI VM](../architecture/stack.md#system-vms)

![Ghaf Secure Laptop](../img/secure_laptop.drawio.png "Secure laptop with custom OS framework Ghaf")


## In This Chapter

- [Running Windows VM on Ghaf](./run_win_vm.md)
- [Running Cuttlefish on Ghaf](./run_cuttlefish.md)
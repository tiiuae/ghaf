<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Running Windows 11 in VM on Ghaf

You can run Windows 11 in a VM on Ghaf with NVIDIA Jetson Orin AGX (ARM64) or Generic x86 device. This method uses [QEMU](https://www.qemu.org/) as VMM. For information on how to build and run a Ghaf image, see [Build and Run](../ref_impl/build_and_run.md).


## Getting Windows 11 Image

1. Depending on the device:
    * For Generic x86, download Windows 11 ISO ([Win11_22H2_English_x64v2.iso](https://www.microsoft.com/software-download/windows11)) from the Microsoft website.
    * For NVIDIA Jetson Orin AGX (ARM64), use your Microsoft account to join the [Windows Insider Program](https://insider.windows.com/en-us/register). On the Windows 11 on Arm Insider Preview page, select the `Windows 11 Client Arm64 Insider Preview (Canary) - Build 25324` build and the language to download a VHDX image file.

2. Copy the image to an external USB drive. Connect the USB drive to the device with the latest version of Ghaf installed, and mount it to some folder.

    ```
    sudo mkdir /mnt
    sudo mount /dev/sda /mnt
    ```
    > **WARNING:** [For NVIDIA Jetson Orin AGX] Make sure to use a fresh VHDX image file that was not booted in another environment before.


## Running Windows 11 in VM

#### Running Windows 11 in VM on ARM64 Device (NVIDIA Jetson Orin AGX)

1. In the Weston terminal, go to the directory with the Windows 11 image and run the VM without sudo and as a non-root user using the following Ghaf script:

    ```
    cd /mnt
    windows-launcher ./Windows11_InsiderPreview_Client_ARM64_en-us_25324.VHDX
    ```

2. Windows 11 requires Internet access to finish the setup. To boot the VM without an Internet connection, open cmd with Shift+F10 and type `OOBE\BYPASSNRO`. After the configuration restart click “I don’t have internet“ to skip the Internet connection step and continue the installation.

    > TIP: If after pressing Shift+F10 the command window is not displayed, try to switch between opened windows by using Alt+Tab.


#### Running Windows 11 in VM on Generic x86 Device

On x86_64 device Windows 11 VM can be launched with either an ISO image or QCOW2:

   * For an ISO image, the script creates an empty QCOW2 image in the same directory which is used as a system disk in the VM.
   * After installing Windows 11, run the script for the QCOW2 image.

Do the folowing:

1. In the Weston terminal, go to the directory with the Windows 11 image and run the VM without sudo and as a non-root user using the following Ghaf script:

    ```
    cd /mnt
    windows-launcher ./Win11_22H2_English_x64v2.iso
    ```

2. When the VM starts booting press any key to boot from a CD.
3. In order to bypass Windows 11 system requirements, open cmd with Shift+F10 and type `regedit`. In HKEY_LOCAL_MACHINE\SYSTEM\Setup, right-click New > Key and type LabConfig. For this key create two DWORD (32-bit) parameters:

   * Name: `BypassTPMCheck`, value `1`.
   * Name: `BypassSecureBootCheck`, value `1`.

   > TIP: [For Ghaf running on a laptop] If after pressing Shift+F10 the command window is not displayed, try again with the Fn key (Shift+Fn+F10) or switch between opened windows by using Alt+Tab.

4. Install Windows 11 in the VM.
5. Windows 11 requires Internet access to finish the setup. To boot the VM without an Internet connection, open cmd with Shift+F10 and type `OOBE\BYPASSNRO`. After the configuration restart click “I don’t have internet“ to skip the Internet connection step and continue the installation.
6. After the installation is completed the script is launched with the QCOW2 image:

    ```
    windows-launcher ./win11.qcow2
    ```

## Using UI to Launch Windows 11 VM

Instead of running Windows launcher from the command line it is possible to launch the Windows 11 VM by clicking the corresponding icon in the Weston taskbar.

When you click it for the first time, you will see a file selection dialog. Once Windows 11 image has been selected, it saves the path to the `~/.config/windows-launcher-ui.conf` configuration file and launches the VM. Next time, the VM will be immediately launched with one click.

In order to use a different image instead of the saved one, delete the configuration file:

   ```
   rm ~/.config/windows-launcher-ui.conf
   ```

## Passing Additional Parameters to QEMU

It is possible to pass additional parameters to QEMU when running Windows launcher from the command line.

NVIDIA Jetson Orin AGX (ARM64) example:

   ```
   windows-launcher ./Windows11_InsiderPreview_Client_ARM64_en-us_25324.VHDX -serial stdio
   ```

Generic x86 example:

   ```
   windows-launcher ./win11.qcow2 -serial stdio
   ```
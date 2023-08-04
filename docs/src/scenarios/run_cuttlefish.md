<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Running Android Cuttlefish Virtual Device on Ghaf

Cuttlefish is a configurable virtual Android device (virtual-machine based Android emulator) that can run both remotely (using third-party cloud offerings such as Google Cloud Engine) and locally (on Linux x86 machines). For more information about Cuttlefish, see the official [Cuttlefish Virtual Android Devices](https://source.android.com/docs/setup/create/cuttlefish) documentation.

You can run Android as a VM on Ghaf for testing and development purposes using NVIDIA Jetson Orin AGX (ARM64) or Generic x86.


## Installing Cuttlefish

1. Download *host_package* (includes binaries and scripts that must be run on the host machine to set up and run the Cuttlefish virtual device) and *aosp_cf_phone-img* (a system image) files from the Android CI server and copy them to Ghaf:

    * For NVIDIA Jetson Orin AGX (ARM64): [cvd-host_package.tar.gz](https://ci.android.com/builds/submitted/9970479/aosp_cf_arm64_phone-userdebug/latest/cvd-host_package.tar.gz) and [aosp_cf_arm64_phone-img-9970479.zip](https://ci.android.com/builds/submitted/9970479/aosp_cf_arm64_phone-userdebug/latest/aosp_cf_arm64_phone-img-9970479.zip)
    * For Generic x86: [cvd-host_package.tar.gz](https://ci.android.com/builds/submitted/9970479/aosp_cf_x86_64_phone-userdebug/latest/cvd-host_package.tar.gz) and [aosp_cf_x86_64_phone-img-9970479.zip](https://ci.android.com/builds/submitted/9970479/aosp_cf_x86_64_phone-userdebug/latest/aosp_cf_x86_64_phone-img-9970479.zip)

    > Download a host package from the same build as the image.

2. Make sure Internet connection is working in Ghaf. If the system gets an IP address but the DNS server is not responding, set the correct date and time.
   
3. [For x86_64 only] Install the required packages:

    ```
    NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nix-env -i python3 openssl bash unzip
    ```

4. Create some hackish links that are required for running Cuttlefish:
   
    ```
    sudo ln -s $(which mv) /bin/mv
    sudo ln -s $(which bash) /bin/bash
    sudo mkdir -p /usr/lib/cuttlefish-common/bin/
    sudo touch /usr/lib/cuttlefish-common/bin/capability_query.py
    sudo chmod 755 /usr/lib/cuttlefish-common/bin/capability_query.py
    sudo groupadd -f cvdnetwork
    sudo usermod -aG cvdnetwork $USER
    sudo usermod -aG kvm $USER
    sudo su ghaf
    ```

5. Change directory to the one that contains host package and image files and extract them:

    * For NVIDIA Jetson Orin AGX (ARM64):
        ```
        tar xvf cvd-host_package.tar.gz
        unzip aosp_cf_arm64_phone-img-9970479.zip
        ```

    * For Generic x86:
        ```
        tar xvf cvd-host_package.tar.gz
        unzip aosp_cf_x86_64_phone-img-9970479.zip
        ```

6. [For x86_64 only] Extra steps to fix missing dependencies:
   * Find ld-linux-x86-64.so.2 and create a link in `/lib64`:

        ```
        sudo find /nix/store -name ld-linux-x86-64.so.2
        sudo mkdir /lib64
        sudo ln -s /nix/store/dg8mpqqykmw9c7l0bgzzb5znkymlbfjw-glibc-2.37-8/lib/ld-linux-x86-64.so.2 /lib64
        ```

   * Find libdrm.so.2 in the `/nix/store` and copy it to the lib64 directory where the host package was extracted:

        ```
        sudo find /nix/store -name libdrm.so.2
        cp /nix/store/2jdx0r0yiz1k38ra0diwqm5akb0k1rjh-libdrm-2.4.115/lib/ ./lib64
        ```


## Running Cuttlefish

Go to the directory with exctacted host package and image files and run Cuttlefish:

```
HOME=$PWD ./bin/launch_cvd -report_anonymous_usage_stats=n
```

It will take some time to load. There should be the following messages in the console when the VM is booted and ready to use:

```
VIRTUAL_DEVICE_DISPLAY_POWER_MODE_CHANGED
VIRTUAL_DEVICE_BOOT_STARTED
VIRTUAL_DEVICE_BOOT_COMPLETED
Virtual device booted successfully
```


## Connecting to Cuttlefish Device

1. Run the Chromium browser by clicking on the corresponding icon in Weston and navigate to <https://localhost:8443>. Ignore a warning about the SSL certificate (“Your connection is not private“) and click **Advanced** > **Proceed to 127.0.0.1 (unsafe)**.

2. Click the **cvd-1 Connect** button. A new tab with an Android VM window will be opened.

3. [Optionally] You can close the browser and use the following command to open a standalone window with an Android VM:

```
chromium-browser --enable-features=UseOzonePlatform --ozone-platform=wayland --new-window --app=https://127.0.0.1:8443/client.html?deviceId=cvd-1
```
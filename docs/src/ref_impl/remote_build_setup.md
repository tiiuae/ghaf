<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Running Remote Build on NixOS

To set up a remote build on NixOS:

1. Identify required SSH keys for remote SSH connection.
2. Set up configurations.

If you hit an issue, check [Troubleshooting](./remote_build_setup.md#troubleshooting).


### 1. Configuring SSH Keys

> [!IMPORTANT]
> This step assumes that public SSH keys were generated and copied (*ssh-copy-id*) both for normal and root users. For more information, see [Setting up public key authentication](https://www.ssh.com/academy/ssh/copy-id#setting-up-public-key-authentication).

Before you begin, make sure an SSH connection is established to the remote host for both normal and root users:

```
ssh USER@IP_ADDRESS_OF_REMOTE_MACHINE
nix store ping --store ssh://USER@REMOTE_IP_ADDRESS
```


#### 1.1. [Local Machine] Configuring SSH Keys

Do the following on a local machine:

1. Change directory to Home Directory with SSH:
    ```
    cd .ssh
    ```

    The public keys of the remote machine are located in the *known_hosts* file. These keys are created and configured after the *ssh-copy-id* command. Make sure the keys are there. If they are not there:

    1. Access the remote machine.
    2. Run `cd /etc/ssh`.
    3. Retrieve and copy the public keys.
    4. Go back to the local machine and paste them into *known_hosts*.


2. Navigate to the `/etc/ssh/` directory:
    ```
    cd /etc/ssh
    ```

    Make sure the *ssh_known_hosts* file contains the same public keys as the remote machine (same as `.ssh/knwon_hosts`). Otherwise, specify it in the `configuration.nix` file.

3. Use CMD as the root user:
   ```
   sudo -i
   ```
4. Make sure the root user’s keys are different from the user’s keys:
   ```
   cd .ssh
   ```
    > `.ssh` is a user-level access and `/etc/ssh` is system-wide.


#### 1.2. Accessing Remote Machine Using SSH

Do the following:

1. Navigate the *authorized_keys* file:
   ```
   ssh USER@IP_ADDRESS_OF_REMOTE_MACHINE
   cd .ssh
   sudo nano authorized_keys
   ```
2. Make sure that both user and root public keys for the local machine are located there:

   * The user’s public key can be obtained from `/home/username/.ssh/id_rsa.pub`.
   * The root user's public key can be obtained from `/root/.ssh/id_rsa.pub`.


### 2. Setting Up Configuration Files

#### 2.1. [Local Machine] Setting Up Configuration Files

Do the following on a local machine:

1. Set configuration variables in `configuration.nix` and `nix.conf`:
   1. Use the following commands:
        ```
        cd /etc/nixos
        sudo nano configuration.nix 
        ```
   2. Add lib in the header like so: `{ config, pkgs, lib, ... }:`.
   3. Edit the `nix.conf` file:
        ```
        environment.etc."nix/nix.conf".text = lib.mkForce ''
            # Your custom nix.conf content here
            builders = @/etc/nix/machines
            require-sigs = false
            max-jobs = 0 # to use remote build by default not local
            substituters = https://cache.nixos.org/
            trusted-public-keys = cache.nixos.org-1:6pb16ZPMQpcDShjY= cache.farah:STwtDRDeIDa...
            build-users-group = nixbld
            trusted-users = root farahayyad
            experimental-features = nix-command flakes
        '';
        ```
        For more information, see the [nix.conf](https://nixos.org/manual/nix/stable/command-ref/conf-file) section of the Nix Reference Manual.
   4. Rebuild NixOS by running:
        ```
        sudo nixos-rebuild switch
        ```
2. Create or set the machines file:
   1. Use the following commands:
        ```
        cd /etc/nixos
        sudo nano machines 
        ```
   2. Specify the SSH settings:
        ```
        [ssh://]USER@HOST target-spec [SSH identity file] [max-jobs] [speed factor]
        [supported-features] [mandatory-features] [ssh-public-key-encoded]
        ```
        * Parameters inside ‘[ ]’ are optional.
        * The ssh-public-key-encoded is the base-64 encoded public key of the remote machine. Get the encoding using:
            ```
            echo -n "your_public_key_here" | base64
            ```
        * If omitted, SSH will use its regular known_hosts file.
  
        For more information, see the [Remote Builds](https://nixos.org/manual/nix/stable/advanced-topics/distributed-builds.html) section of the Nix Reference Manual.


#### 2.2. [Remote Machine] Setting Up Configuration Files

Do the following on a remote machine:

1. Specify the sshd_config settings:
   1. Use the following commands:
        ```
        cd /etc/ssh
        sudo nano sshd_config
        ```
   2. Make sure *PubkeyAuthentication* is set as *yes*.
2. Specify the `/etc/nix/nix.conf` settings:
   1. Use the following commands:
        ```
        cd /etc/nix
        sudo nano nix.conf
        ```
   2. Edit the `nix.conf` file:
        ```
        trusted-public-keys = cache.nixos.org-1:61o0gWypbMrAURk...
        build-users-group = nixbld
        require-sigs = false
        trusted-users = root farahayyad jk
        binary-caches = https://cache.nixos.org/
        substituters = https://cache.nixos.org/
        system-features = nixos-test benchmark big-parallel kvm
        binary-cache-public-keys = cache.nixos.org-1:6NCHD59X43...
        experimental-features = nix-command flakes
        ```
   3. Run the following command to restart daemon and update all the preceding changes:
        ```
        systemctl restart nix-daemon.service
        ```


## Troubleshooting

* [Single-User Nix Installation Issues](./remote_build_setup.md#single-user-nix-installation-issues)
* [VPN Setup for Remote Access](./remote_build_setup.md#vpn-setup-for-remote-access)
* [Private Key on Local Machine Not Matching Public Key on Remote Machine](./remote_build_setup.md#private-key-on-local-machine-not-matching-public-key-on-remote-machine)


### Single-User Nix Installation Issues

This issue typically arises when Nix is installed in a single-user mode on the remote machine, which can create permission issues during multi-user operations.

If an operation fails with the following error message:

```
could not set permissions on '/nix/var/nix/profiles/per-user' to 755: Operation not permitted
```

reinstall Nix in a multi-user setup:

* Uninstall Nix using a single-user mode:

    ```
    rm -rf /nix
    ```
* Install Nix in a multi-user mode:

    ```
    sh <(curl -L https://nixos.org/nix/install) --daemon
    ```

For more information about Nix security modes, see the [Security](https://nixos.org/manual/nix/stable/installation/nix-security) section of the Nix Reference Manual.


### VPN Setup for Remote Access

A VPN is needed, if the local machine is not on the same local network as your remote build machine. 

To set up a VPN using [OpenConnect](https://www.infradead.org/openconnect/), do the following:

* Install OpenConnect:

```
nix-env -iA nixos.openconnect
```

* Establish a VPN connection:

```
sudo openconnect --protocol=gp -b access.tii.ae
```

* Once authenticated, you establish a secure connection to your network. Use `ssh USER@IP_ADDRESS_OF_REMOTE_MACHINE` to check if it is possible to connect to the remote machine.


### Private Key on Local Machine Not Matching Public Key on Remote Machine

Using mismatched key pairs could result in the Permission denied error.

Ensure and double-check that you are using the right key pairs.

If you choose to use/present your local’s RSA private key, make sure that it is the corresponding RSA public key that is in the remote’s authorized_file, not the ED25519 or ECDSA public keys.
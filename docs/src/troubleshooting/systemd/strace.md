<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Use `strace` to debug initialization sequence

`strace` can give detailed insight about system calls made by a service. This is very helpfull in debugging restrictions applied on system calls and capability of any service. Though we can attach `strace` with PID of  a running process, but some time we may need to debug service initialization sequence also.

To debug initialization sequence we need to attach `strace` with the service binary in `ExecStart` . To attach strace find out existing `ExecStart` of the service using command:

```bash
$> systemctl cat <service-name>.service | grep ExecStart
```

It will give  command line options used with service binary. Now we need to override `ExecStart` of the service, in order to attach `strace`. We'll use same options with `strace`too to replicate same scenario. For example to attach `strace` with `auditd` service we'll use following configuration at a suitable location:

```Nix
systemd.services."auditd".serviceConfig.ExecStart = lib.mkForce "${pkgs.strace}/bin/strace -o /etc/auditd_trace.log ${pkgs.audit}/bin/auditd -l -n -s nochange";
```

Command`${pkgs.audit}/bin/auditd -l -n -s nochange`is used in regular `ExecStart`of `auditd`service. In above command we have attached `strace` with the command, which will generate system call traces in file `/etc/auditd_trace.log`

After modifying above configuration you need to rebuild and load Ghaf image. 

The log may give you information about the system call restriction which caused the service failure. You can tune your service config accordingly.

<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# `systemd-analyze` Tool

`systemd-analyze` is a powerful tool that helps diagnose and troubleshoot issues related to systemd services. It provides various commands to analyze the performance and dependencies of services, as well as to pinpoint issues during the boot process.

### Steps to Analyze Systemd Services

#### 1. **Analyze Boot Performance**

`systemd-analyze` can help you understand how long each service takes to start during boot. This is useful for identifying services that are slowing down the boot process.


* To get a summary of the boot time:

  ```bash
  $> systemd-analyze
  ```

  This command shows the overall time taken to boot, including the kernel, initrd, and userspace times.
* To see a detailed breakdown of how long each service took to start:

  ```bash
  $> systemd-analyze blame
  ```

  This lists all services in order of their startup time, with the slowest services listed first.
* For a graphical representation of the boot process, you can use:

  ```bash
  $> system-analyze plot > boot-time.svg
  ```

  This command generates an SVG file that visually represents the startup times of all services. You can view this file in any web browser.

#### 2.  View Service Dependencies

To troubleshoot issues related to service dependencies, you can visualize the dependency tree of a specific service. To display the dependency tree of a service:

```bash
systemd-analyze critical-chain <service_name>.service
```

This command shows the critical path that affects the startup time of the service, highlighting any dependencies that may delay its startup.


#### 3. Verify Unit Files

To verify the configuration of a service's unit file:

-  ```bash
  $> systemd-analyze verify <service-name>.service
  ```

  This command checks the syntax and can help identify configuration issues.

#### 4. Check for Cyclic Dependencies

Cyclic dependencies can cause services to fail or hang during boot. systemd-analyze can check for these issues:

- To check for any cyclic dependencies:

  ```
  $> systemd-analyze verify --man=your-service-name.service
  ```

  This will warn you about any loops or issues within the unit's dependency tree.



#### 5. Analyze Security Settings

`systemd-analyze` can also assess the security of your service’s configuration:

- To evaluate the overall threat exposure of systemd services, use:

  ```bash
  $> systemd-analyze security
  ```
- To evaluate the security of a specific service:

  ```bash
  $> systemd-analyze security <service-name>.service
  ```
  This command provides a security assessment, scoring the service based on various hardening options and highlighting potential weaknesses.

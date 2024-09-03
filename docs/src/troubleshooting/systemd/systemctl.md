<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Debuuging systemd using`systemctl`

To debug failed services using `systemctl` follow below given steps:

1) List failed services in the system:

   ```bash
   $> sudo systemctl --failed
   ```

   Above command will give you list of failed services. You can see list of all the services in the system using the command:

   ```
   $> sudo systemctl list-unit-files --type=service
   ```

2. Check status of the failed service, it will you give little more detailed information.

   ```bash
   $> sudo systemctl status <service_name>.service
   ```
3. See the service logs to get more insight:

   ```
   $> sudo journalctl -b -u <service_name>.service
   ```
4. You can further increase log level to get debug level information:

   ```bash
   $> sudo systemctl log-level debug
   ```

   Reload the systemd daemon and restart service:

   ```bash
   $> sudo systemctl daemon-reload
   $> sudo systemctl restart  <service_name>.service
   ```

   Now you can see debug level information in the service log.
5. You can also attach `strace` with the service daemon to see system call and signal status.

   - Get the PID of main process from service status. It is listed as `Main PID:`
   - Attach strace with the PID:

     ```bash
     $> sudo strace -f -s 100 -p <Main_PID>
     ```
6. Retune the service configuration in runtime:

   ```bash
   $> systemctl edit --runtime <service_name>.service
   ```

   - Uncomment the `[Service]`section and also uncomment the configuration you want to enable or disable. You can add any new configuration. This basically overrides your base configuration.
   - Save the configuration as `/run/systemd/system/<service_name>.d/override.conf`
   - Reload the systemd daemon and restart the service as mentioned in step 4.
   - You can check if your service is using the new configuration using command:

     ```
     $> sudo systemctl show <service_name>.service
     ```
   - You see base configuration also:

     ```bash
     $> sudo systemctl cat <service_name>.service
     ```
7. If the new configuration works for you, you can check the exposure level of the service using command:

   ```bash
   $> systemd-analyze security
   $> systemd-analyze security <service_name>.service #For detailed information
   ```
8. Update the configuration in Ghaf repo and build it. Hardened service configs are available in directory `ghaf/modules/common/systemd/hardened-configs`

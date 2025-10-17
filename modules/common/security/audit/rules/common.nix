# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  lib,
  ...
}:
let
  passwordFilesLocation =
    if config.services.userborn.enable then config.services.userborn.passwordFilesLocation else "/etc";
in
[
  ## === Common :: Nix/NixOS-specific ===
  "-a always,exit -F arch=b64 -S execve -F exe=${pkgs.nix}/bin/nix-daemon -k nix-daemon-exec"
  "-a always,exit -F arch=b64 -S execve -S execveat -F exe=${pkgs.nix}/bin/nix -F auid>=1000 -F auid!=unset -k nix-tools"
  "-w ${pkgs.nix}/bin/nix -p x -k nix-exec"
  "-w ${pkgs.nix}/bin/nix-store -p x -k nix-store"
  "-w ${pkgs.nix}/bin/nix-shell -p x -k nix-exec"
  "-w ${pkgs.nix}/bin/nix-collect-garbage -p x -k nix-gc"
  "-w ${pkgs.nix}/bin/nix-build -p x -k nix-build"
  # nixos-rebuild is a separate package
  "-w ${pkgs.nixos-rebuild}/bin/nixos-rebuild -p x -k nix-syschange"
  # System-wide config
  "-w /etc/nix -p wa -k nix_conf"
  "-w /etc/nixos -p wa -k nixos_conf"
  "-w /etc/systemd/system/nix-daemon.service.d -p wa -k nix_daemon_unit"
  "-w /etc/systemd/system/nix-daemon.service -p wa -k nix_daemon_unit"
  "-w /etc/systemd/system/nix-daemon.socket -p war -k nix_daemon_unit"
  "-w /etc/systemd/system/sockets.target.wants/nix-daemon.socket -p wa -k nix_daemon_unit"

  ## === Common :: STIG-derived ===
  # Rules borrowed from https://stigviewer.com/stigs/anduril_nixos
  # V-268091
  "-a always,exit -F arch=b64 -S execve -C uid!=euid -F euid=0 -k execpriv"
  "-a always,exit -F arch=b64 -S execve -C gid!=egid -F egid=0 -k execpriv "
  # V-268094
  "-a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=-1 -k privileged-mount"
  # V-268164
  "-a always,exit -F path=/run/current-system/sw/bin/usermod -F perm=x -F auid>=1000 -F auid!=-1 -k privileged-usermod"
  # V-268165
  "-a always,exit -S all -F path=/run/current-system/sw/bin/chage -F perm=x -F auid>=1000 -F auid!=-1 -k privileged-chage"
  "-a always,exit -S all -F path=/run/current-system/sw/bin/chcon -F perm=x -F auid>=1000 -F auid!=-1 -k perm_mod"
  # V-268167
  "-w /etc/sudoers -p wa -k identity"
  "-w /etc/passwd -p wa -k identity"
  "-w /etc/shadow -p wa -k identity"
  "-w /etc/group -p wa -k identity"
  # V-268166
  "-w /var/log/lastlog -p wa -k logins"
  # V-268163
  "-a always,exit -F arch=b64 -S setxattr,fsetxattr,lsetxattr,removexattr,fremovexattr,lremovexattr -F auid>=1000 -F auid!=-1 -k perm_mod"
  "-a always,exit -F arch=b64 -S setxattr,fsetxattr,lsetxattr,removexattr,fremovexattr,lremovexattr -F auid=0 -k perm_mod"
  # V-268099
  "-a always,exit -F arch=b64 -S chown,fchown,lchown,fchownat -F auid>=1000 -F auid!=unset -F key=perm_mod"
  # V-268098
  "-a always,exit -F arch=b64 -S open,creat,truncate,ftruncate,openat,open_by_handle_at -F exit=-EACCES -F auid>=1000 -F auid!=unset -F key=access"
  "-a always,exit -F arch=b64 -S open,creat,truncate,ftruncate,openat,open_by_handle_at -F exit=-EPERM -F auid>=1000 -F auid!=unset -F key=access"
  # V-268096
  "-a always,exit -F arch=b64 -S init_module,finit_module,delete_module -F auid>=1000 -F auid!=unset -k module_chng"
  # V-268095
  "-a always,exit -F arch=b64 -S rename,unlink,rmdir,renameat,unlinkat -F auid>=1000 -F auid!=unset -k delete"
  # V-268100
  "-a always,exit -F arch=b64 -S chmod,fchmod,fchmodat -F auid>=1000 -F auid!=unset -F key=perm_mod"

  ## === Common :: OSPP-derived ===
  # 11-loginuid.rules && V-268119
  "--loginuid-immutable"

  ## === Common :: Other ===
  "-a always,exit -F arch=b64 -F path=/etc/machine-id -F perm=wa -F key=identity"
  "-w /etc/ssh -p rwxa -k ssh_config_access"
  # User root execve
  "-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=unset -k privileged-execve"

  # 32-power-abuse.rules
  ## The purpose of this rule is to detect when an admin may be abusing power
  ## by looking in user's home dir.
  # "-a always,exit -F dir=/home -F uid=0 -F auid>=1000 -F auid!=unset -C auid!=obj_uid -F key=power-abuse"

  # 42-injection.rules
  ## These rules watch for code injection by the ptrace facility.
  ## This could indicate someone trying to do something bad or
  ## just debugging
  "-a always,exit -F arch=b64 -S ptrace -F key=tracing"
  "-a always,exit -F arch=b64 -S ptrace -F a0=0x4 -F key=code-injection"
  "-a always,exit -F arch=b64 -S ptrace -F a0=0x5 -F key=data-injection"
  "-a always,exit -F arch=b64 -S ptrace -F a0=0x6 -F key=register-injection"

  # 43-module-load.rules
  ## These rules watch for kernel module insertion. By monitoring
  ## the syscall, we do not need any watches on programs.
  "-a always,exit -F arch=b64 -S init_module,finit_module -F key=module-load"
  "-a always,exit -F arch=b64 -S delete_module -F key=module-unload"

  # 44-installers.rules
  # These rules watch for invocation of things known to install software
  # TODO Handle this in a more generic way

  # 99-finalize.rules
  # COMMENT: Handled by nixos module
]
++ lib.optionals config.ghaf.security.audit.enableVerboseCommon [
  # 70-einval.rules
  ## These are rules are to locate poorly written programs.
  ## Its never planned to waste time on a syscall with incorrect parameters
  ## This is more of a debugging step than something people should run with
  ## in production.
  # This spams the logs significantly, but also may hint at some misconfigurations.
  "-a never,exit -F arch=b64 -S rt_sigreturn"
  "-a always,exit -S all -F exit=-EINVAL -F key=einval-retcode"
]
++ lib.optionals config.ghaf.security.audit.enableStig [
  ## STIG RULES ##

  ## (GEN002880: CAT II) The IAO will ensure the auditing software can
  ## record the following for each audit event:
  ##- Date and time of the event
  ##- Userid that initiated the event
  ##- Type of event
  ##- Success or failure of the event
  ##- For I&A events, the origin of the request (e.g., terminal ID)
  ##- For events that introduce an object into a user’s address space, and
  ##  for object deletion events, the name of the object, and in MLS
  ##  systems, the object’s security level.
  ##
  ## Things that could affect time
  "-a always,exit -F arch=b64 -S adjtimex,settimeofday -F key=time-change"
  "-a always,exit -F arch=b64 -S clock_settime -F a0=0x0 -F key=time-change"
  # Introduced in 2.6.39, commented out because it can make false positives
  # "-a always,exit -F arch=b64 -S clock_adjtime -F key=time-change"
  "-a always,exit -F arch=b64 -F path=/etc/localtime -F perm=wa -F key=time-change"
  ## Things that affect identity
  # Handled in common rules - V-268167
  "-a always,exit -F arch=b64 -F path=${passwordFilesLocation}/group -F perm=wa -F key=identity"
  "-a always,exit -F arch=b64 -F path=${passwordFilesLocation}/passwd -F perm=wa -F key=identity"
  "-a always,exit -F arch=b64 -F path=${passwordFilesLocation}/shadow -F perm=wa -F key=identity"
  ## Things that could affect system locale
  "-a always,exit -F arch=b64 -S sethostname,setdomainname -F key=system-locale"
  "-a always,exit -F arch=b64 -F path=/etc/issue -F perm=wa -F key=system-locale"
  "-a always,exit -F arch=b64 -F path=/etc/issue.net -F perm=wa -F key=system-locale"
  "-a always,exit -F arch=b64 -F path=/etc/hosts -F perm=wa -F key=system-locale"
  "-a always,exit -F arch=b64 -F path=/etc/hostname -F perm=wa -F key=system-locale"
  # "-a always,exit -F arch=b64 -F dir=/etc/NetworkManager/ -F perm=wa -F key=system-locale"
  ## Things that could affect MAC policy
  #"-a always,exit -F arch=b64 -F dir=/etc/selinux/ -F perm=wa -F key=MAC-policy"

  ## (GEN002900: CAT III) The IAO will ensure audit files are retained at
  ## least one year; systems containing SAMI will be retained for five years.
  ##
  ## Site action - no action in config files
  ## (GEN002920: CAT III) The IAO will ensure audit files are backed up
  ## no less than weekly onto a different system than the system being
  ## audited or backup media.
  ##
  ## Can be done with cron script
  ## (GEN002700: CAT I) (Previously – G095) The SA will ensure audit data
  ## files have permissions of 640, or more restrictive.
  ##
  ## Done automatically by auditd
  ## (GEN002720-GEN002840: CAT II) (Previously – G100-G106) The SA will
  ## configure the auditing system to audit the following events for all
  ## users and root:
  ##
  ## - Logon (unsuccessful and successful) and logout (successful)
  ##
  ## Handled by pam, sshd, login, and gdm
  ## Might also want to watch these files if needing extra information
  # "-a always,exit -F arch=b64 -F path=/var/log/tallylog -F perm=wa -F key=logins"
  # "-a always,exit -F arch=b64 -F path=/var/run/faillock -F perm=wa -F key=logins"
  "-a always,exit -F arch=b64 -F path=/var/log/lastlog -F perm=wa -F key=logins"

  ##- Process and session initiation (unsuccessful and successful)
  ##
  ## The session initiation is audited by pam without any rules needed.
  ## Might also want to watch this file if needing extra information
  # "-a always,exit -F arch=b64 -F path=/var/run/utmp -F perm=wa -F key=session"
  # "-a always,exit -F arch=b64 -F path=/var/log/btmp -F perm=wa -F key=session"
  "-a always,exit -F arch=b64 -F path=/var/log/wtmp -F perm=wa -F key=session"

  ##- Discretionary access control permission modification (unsuccessful
  ## and successful use of chown/chmod)
  # Handled in common rules - (V-268163, V-268099, V-268100)
  # "-a always,exit -F arch=b64 -S chown,fchown,lchown,fchownat -F auid>=1000 -F auid!=unset -F key=perm_mod"
  # "-a always,exit -F arch=b64 -S setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F auid>=1000 -F auid!=unset -F key=perm_mod"

  ##- Unauthorized access attempts to files (unsuccessful)
  # Handled partially in common rules - V-268098
  "-a always,exit -F arch=b64 -S open,truncate,ftruncate,creat,openat,openat2,open_by_handle_at -F exit=-EACCES -F auid>=1000 -F auid!=unset -F key=access"
  "-a always,exit -F arch=b64 -S open,truncate,ftruncate,creat,openat,openat2,open_by_handle_at -F exit=-EPERM -F auid>=1000 -F auid!=unset -F key=access"

  ##- Use of print command (unsuccessful and successful)
  ##- Export to media (successful)
  ## You have to mount media before using it. You must disable all automounting
  ## so that its done manually in order to get the correct user requesting the
  ## export
  # "-a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=unset -F key=export"

  ##- System startup and shutdown (unsuccessful and successful)
  ##- Files and programs deleted by the user (successful and unsuccessful)
  # Handled partially in common rules - V-268095
  "-a always,exit -F arch=b64 -S unlink,unlinkat,rename,renameat -F auid>=1000 -F auid!=unset -F key=delete"

  ##- All system administration actions
  ##- All security personnel actions
  ##
  ## Look for pam_tty_audit and add it to your login entry point's pam configs.
  ## If that is not found, use sudo which should be patched to record its
  ## commands to the audit system. Do not allow unrestricted root shells or
  ## sudo cannot record the action.
  # Handled in common rules - V-268167
  # "-a always,exit -F arch=b64 -F path=/etc/sudoers -F perm=wa -F key=actions"
  # "-a always,exit -F arch=b64 -F dir=/etc/sudoers.d/ -F perm=wa -F key=actions"

  ## Special case for systemd-run. It is not audit aware, specifically watch it
  # "-a always,exit -F arch=b64 -F path=${pkgs.systemd}/bin/systemd-run -F perm=x -F auid!=unset -F key=maybe-escalation"

  ## Special case for pkexec. It is not audit aware, specifically watch it
  # "-a always,exit -F arch=b64 -F path=/usr/bin/pkexec -F perm=x -F key=maybe-escalation"
  ## (GEN002860: CAT II) (Previously – G674) The SA and/or IAO will
  ##ensure old audit logs are closed and new audit logs are started daily.
  ##
  ## Site action. Can be assisted by a cron job
]
++ lib.optionals config.ghaf.security.audit.enableOspp [

  ## Operating System Protection Profile (OSPP)v4.2 ##

  ## The purpose of these rules is to meet the requirements for Operating
  ## System Protection Profile (OSPP)v4.2. These rules depends on having
  ## the following rule files copied to /etc/audit/rules.d:
  ##
  ## 10-base-config.rules, 11-loginuid.rules,
  ## 30-ospp-v42-1-create-failed.rules, 30-ospp-v42-1-create-success.rules,
  ## 30-ospp-v42-2-modify-failed.rules, 30-ospp-v42-2-modify-success.rules,
  ## 30-ospp-v42-3-access-failed.rules, 30-ospp-v42-3-access-success.rules,
  ## 30-ospp-v42-4-delete-failed.rules, 30-ospp-v42-4-delete-success.rules,
  ## 30-ospp-v42-5-perm-change-failed.rules,
  ## 30-ospp-v42-5-perm-change-success.rules,
  ## 30-ospp-v42-6-owner-change-failed.rules,
  ## 30-ospp-v42-6-owner-change-success.rules
  ##
  ## original copies may be found in /usr/share/audit-rules

  ## 10-base-config.rules:
  # handled by nixos module

  ## 11-loginuid.rules
  # Handled in common rules - V-268119

  ## 30-ospp-v42-1-create-failed.rules
  ## Unsuccessful file creation (open with O_CREAT)
  "-a always,exit -F arch=b64 -S openat,open_by_handle_at -F a2&0100 -F exit=-EACCES -F auid>=1000 -F auid!=unset -F key=unsuccessful-create"
  "-a always,exit -F arch=b64 -S open -F a1&0100 -F exit=-EACCES -F auid>=1000 -F auid!=unset -F key=unsuccessful-create"
  "-a always,exit -F arch=b64 -S creat -F exit=-EACCES -F auid>=1000 -F auid!=unset -F key=unsuccessful-create"
  "-a always,exit -F arch=b64 -S openat,open_by_handle_at -F a2&0100 -F exit=-EPERM -F auid>=1000 -F auid!=unset -F key=unsuccessful-create"
  "-a always,exit -F arch=b64 -S open -F a1&0100 -F exit=-EPERM -F auid>=1000 -F auid!=unset -F key=unsuccessful-create"
  "-a always,exit -F arch=b64 -S creat -F exit=-EPERM -F auid>=1000 -F auid!=unset -F key=unsuccessful-create"
  ## 30-ospp-v42-1-create-success.rules
  ## Successful file creation (open with O_CREAT)
  "-a always,exit -F arch=b64 -S openat,open_by_handle_at -F a2&0100 -F success=1 -F auid>=1000 -F auid!=unset -F key=successful-create"
  "-a always,exit -F arch=b64 -S open -F a1&0100 -F success=1 -F auid>=1000 -F auid!=unset -F key=successful-create"
  "-a always,exit -F arch=b64 -S creat -F success=1 -F auid>=1000 -F auid!=unset -F key=successful-create"

  ## 30-ospp-v42-2-modify-failed.rules
  ## Unsuccessful file modifications (open for write or truncate)
  "-a always,exit -F arch=b64 -S openat,open_by_handle_at -F a2&01003 -F exit=-EACCES -F auid>=1000 -F auid!=unset -F key=unsuccessful-modification"
  "-a always,exit -F arch=b64 -S open -F a1&01003 -F exit=-EACCES -F auid>=1000 -F auid!=unset -F key=unsuccessful-modification"
  "-a always,exit -F arch=b64 -S truncate,ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=unset -F key=unsuccessful-modification"
  "-a always,exit -F arch=b64 -S openat,open_by_handle_at -F a2&01003 -F exit=-EPERM -F auid>=1000 -F auid!=unset -F key=unsuccessful-modification"
  "-a always,exit -F arch=b64 -S open -F a1&01003 -F exit=-EPERM -F auid>=1000 -F auid!=unset -F key=unsuccessful-modification"
  "-a always,exit -F arch=b64 -S truncate,ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=unset -F key=unsuccessful-modification"
  ## 30-ospp-v42-2-modify-success.rules
  ## Successful file modifications (open for write or truncate)
  "-a always,exit -F arch=b64 -S openat,open_by_handle_at -F a2&01003 -F success=1 -F auid>=1000 -F auid!=unset -F key=successful-modification"
  "-a always,exit -F arch=b64 -S open -F a1&01003 -F success=1 -F auid>=1000 -F auid!=unset -F key=successful-modification"
  "-a always,exit -F arch=b64 -S truncate,ftruncate -F success=1 -F auid>=1000 -F auid!=unset -F key=successful-modification"

  ## 30-ospp-v42-3-access-failed.rules
  ## Unsuccessful file access (any other opens) This has to go last.
  "-a always,exit -F arch=b64 -S open,openat,openat2,open_by_handle_at -F exit=-EACCES -F auid>=1000 -F auid!=unset -F key=unsuccessful-access"
  "-a always,exit -F arch=b64 -S open,openat,openat2,open_by_handle_at -F exit=-EPERM -F auid>=1000 -F auid!=unset -F key=unsuccessful-access"

  ## 30-ospp-v42-4-delete-failed.rules
  ## Unsuccessful file delete
  "-a always,exit -F arch=b64 -S unlink,unlinkat,rename,renameat -F exit=-EACCES -F auid>=1000 -F auid!=unset -F key=unsuccessful-delete"
  "-a always,exit -F arch=b64 -S unlink,unlinkat,rename,renameat -F exit=-EPERM -F auid>=1000 -F auid!=unset -F key=unsuccessful-delete"

  ## 30-ospp-v42-4-delete-success.rules
  ## Successful file delete
  "-a always,exit -F arch=b64 -S unlink,unlinkat,rename,renameat -F success=1 -F auid>=1000 -F auid!=unset -F key=successful-delete"

  ## 30-ospp-v42-5-perm-change-failed.rules
  ## Unsuccessful permission change
  "-a always,exit -F arch=b64 -S chmod,fchmod,fchmodat,setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F exit=-EACCES -F auid>=1000 -F auid!=unset -F key=unsuccessful-perm-change"
  "-a always,exit -F arch=b64 -S chmod,fchmod,fchmodat,setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F exit=-EPERM -F auid>=1000 -F auid!=unset -F key=unsuccessful-perm-change"

  ## 30-ospp-v42-5-perm-change-success.rules
  ## Successful permission change
  "-a always,exit -F arch=b64 -S chmod,fchmod,fchmodat,setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F success=1 -F auid>=1000 -F auid!=unset -F key=successful-perm-change"

  ## 30-ospp-v42-6-owner-change-failed.rules
  ## Unsuccessful ownership change
  "-a always,exit -F arch=b64 -S lchown,fchown,chown,fchownat -F exit=-EACCES -F auid>=1000 -F auid!=unset -F key=unsuccessful-owner-change"
  "-a always,exit -F arch=b64 -S lchown,fchown,chown,fchownat -F exit=-EPERM -F auid>=1000 -F auid!=unset -F key=unsuccessful-owner-change"

  ## 30-ospp-v42-6-owner-change-success.rules
  ## Successful ownership change
  "-a always,exit -F arch=b64 -S lchown,fchown,chown,fchownat -F success=1 -F auid>=1000 -F auid!=unset -F key=successful-owner-change"

  ## User add delete modify. This is covered by pam. However, someone could
  ## open a file and directly create or modify a user, so we'll watch passwd and
  ## shadow for writes
  "-a always,exit -F arch=b64 -S openat,open_by_handle_at -F a2&03 -F path=/etc/passwd -F auid>=1000 -F auid!=unset -F key=user-modify"
  "-a always,exit -F arch=b64 -S open -F a1&03 -F path=/etc/passwd -F auid>=1000 -F auid!=unset -F key=user-modify"
  "-a always,exit -F arch=b64 -S openat,open_by_handle_at -F a2&03 -F path=/etc/shadow -F auid>=1000 -F auid!=unset -F key=user-modify"
  "-a always,exit -F arch=b64 -S open -F a1&03 -F path=/etc/shadow -F auid>=1000 -F auid!=unset -F key=user-modify"

  ## User enable and disable. This is entirely handled by pam.
  ## Group add delete modify. This is covered by pam. However, someone could
  ## open a file and directly create or modify a user, so we'll watch group and
  ## gshadow for writes
  "-a always,exit -F arch=b64 -F path=${passwordFilesLocation}/passwd -F perm=wa -F auid>=1000 -F auid!=unset -F key=user-modify"
  "-a always,exit -F arch=b64 -F path=${passwordFilesLocation}/shadow -F perm=wa -F auid>=1000 -F auid!=unset -F key=user-modify"
  "-a always,exit -F arch=b64 -F path=${passwordFilesLocation}/group -F perm=wa -F auid>=1000 -F auid!=unset -F key=group-modify"
  # "-a always,exit -F arch=b64 -F path=${passwordFilesLocation}/gshadow -F perm=wa -F auid>=1000 -F auid!=unset -F key=group-modify"

  ## Use of special rights for config changes. This would be use of setuid
  ## programs that relate to user accts. This is not all setuid apps because
  ## requirements are only for ones that affect system configuration.
  ## TODO Handle wrappers / setuid binaries
  # "-a always,exit -F arch=b64 -F path=/usr/sbin/unix_chkpwd -F perm=x -F auid>=1000 -F auid!=unset -F key=special-config-changes"
  # "-a always,exit -F arch=b64 -F path=/usr/sbin/usernetctl -F perm=x -F auid>=1000 -F auid!=unset -F key=special-config-changes"
  # "-a always,exit -F arch=b64 -F path=/usr/sbin/userhelper -F perm=x -F auid>=1000 -F auid!=unset -F key=special-config-changes"
  # "-a always,exit -F arch=b64 -F path=/usr/sbin/seunshare -F perm=x -F auid>=1000 -F auid!=unset -F key=special-config-changes"
  # "-a always,exit -F arch=b64 -F path=/usr/bin/mount -F perm=x -F auid>=1000 -F auid!=unset -F key=special-config-changes"
  # "-a always,exit -F arch=b64 -F path=/usr/bin/newgrp -F perm=x -F auid>=1000 -F auid!=unset -F key=special-config-changes"
  # "-a always,exit -F arch=b64 -F path=/usr/bin/newuidmap -F perm=x -F auid>=1000 -F auid!=unset -F key=special-config-changes"
  # "-a always,exit -F arch=b64 -F path=/usr/bin/gpasswd -F perm=x -F auid>=1000 -F auid!=unset -F key=special-config-changes"
  # "-a always,exit -F arch=b64 -F path=/usr/bin/newgidmap -F perm=x -F auid>=1000 -F auid!=unset -F key=special-config-changes"
  # "-a always,exit -F arch=b64 -F path=/usr/bin/umount -F perm=x -F auid>=1000 -F auid!=unset -F key=special-config-changes"
  # "-a always,exit -F arch=b64 -F path=/usr/bin/passwd -F perm=x -F auid>=1000 -F auid!=unset -F key=special-config-changes"
  # "-a always,exit -F arch=b64 -F path=/usr/bin/crontab -F perm=x -F auid>=1000 -F auid!=unset -F key=special-config-changes"
  # "-a always,exit -F arch=b64 -F path=/usr/bin/at -F perm=x -F auid>=1000 -F auid!=unset -F key=special-config-changes"
  # "-a always,exit -F arch=b64 -F path=/usr/sbin/grub2-set-bootflag -F perm=x -F auid>=1000 -F auid!=unset -F key=special-config-changes"

  ## Privilege escalation via su or sudo. This is entirely handled by pam.
  ## Special case for systemd-run. It is not audit aware, specifically watch it
  "-a always,exit -F arch=b64 -F path=${pkgs.systemd}/bin/systemd-run -F perm=x -F auid!=unset -F key=maybe-escalation"

  ## Special case for pkexec. It is not audit aware, specifically watch it
  # TODO Handle kexec
  # "-a always,exit -F arch=b64 -F path=/usr/bin/pkexec -F perm=x -F key=maybe-escalation"

  ## Watch for configuration changes to privilege escalation.
  # COMMENT: No writes possible
  # "-a always,exit -F arch=b64 -F path=/etc/sudoers -F perm=wa -F key=special-config-changes"
  # "-a always,exit -F arch=b64 -F dir=/etc/sudoers.d/ -F perm=wa -F key=special-config-changes"

  ## Audit log access
  "-a always,exit -F arch=b64 -F dir=/var/log/audit/ -F perm=r -F auid>=1000 -F auid!=unset -F key=access-audit-trail"

  ## Attempts to Alter Process and Session Initiation Information
  # "-a always,exit -F arch=b64 -F path=/var/run/utmp -F perm=wa -F auid>=1000 -F auid!=unset -F key=session"
  # "-a always,exit -F arch=b64 -F path=/var/log/btmp -F perm=wa -F auid>=1000 -F auid!=unset -F key=session"
  "-a always,exit -F arch=b64 -F path=/var/log/wtmp -F perm=wa -F auid>=1000 -F auid!=unset -F key=session"

  ## Attempts to modify MAC controls
  ## COMMENT: N/A
  # "-a always,exit -F arch=b64 -F dir=/etc/selinux/ -F perm=wa -F auid>=1000 -F auid!=unset -F key=MAC-policy"

  ## Software updates. This is entirely handled by rpm.
  ## System start and shutdown. This is entirely handled by systemd
  ## Kernel Module loading. This is handled in 43-module-load.rules
  ## Application invocation. The requirements list an optional requirement
  ## FPT_SRP_EXT.1 Software Restriction Policies. This event is intended to
  ## state results from that policy. This would be handled entirely by
  ## that daemon.
]
++ lib.optionals config.ghaf.security.audit.enableVerboseOspp [
  ## 30-ospp-v42-3-access-success.rules
  ## Successful file access (any other opens) This has to go last.
  ## This are likely to result in a whole lot of events
  "-a always,exit -F arch=b64 -S open,openat,openat2,open_by_handle_at -F success=1 -F auid>=1000 -F auid!=unset -F key=successful-access"
]

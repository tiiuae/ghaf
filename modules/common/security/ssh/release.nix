# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.security.ssh.release;
  ghafUser = config.ghaf.users.admin.name;
  hasKeys = cfg.authorizedKeys != [ ];
  hasCA = cfg.trustedUserCAKeys != [ ];
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    concatStringsSep
    concatMapStringsSep
    optional
    ;
in
{
  _file = ./release.nix;

  options.ghaf.security.ssh.release = {
    enable = mkEnableOption "hardened release SSH (certificate and/or authorized-key auth)";

    authorizedKeys = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Static authorized public keys (authorized_keys line format). Hardware-backed
        sk-ssh-ed25519@openssh.com (YubiKey/FIDO2) keys are strongly recommended. Written to
        a system-level /etc/ssh/authorized_keys.d/<ghaf-user> file, each prefixed with
        authorizedKeysOptions. Never-expiring; serves as break-glass alongside a CA.
      '';
    };

    trustedUserCAKeys = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        SSH user-CA public keys. Operators present certificates signed by one of these CAs.
        Written to /etc/ssh/trusted_user_ca.pub and referenced by TrustedUserCAKeys.
      '';
    };

    allowedPrincipals = mkOption {
      type = types.listOf types.str;
      default = [ ghafUser ];
      description = ''
        Certificate principals accepted for login (CA backend only). Written to
        /etc/ssh/authorized_principals/<ghaf-user> and referenced by AuthorizedPrincipalsFile.
      '';
    };

    authorizedKeysOptions = mkOption {
      type = types.str;
      default = "restrict,pty,port-forwarding,verify-required";
      description = ''
        authorized_keys per-key options prefix applied to every authorizedKeys entry.
        `restrict` denies everything by default (agent/X11/user-rc), then specific
        capabilities are re-enabled: `pty` (terminal), `port-forwarding` (REQUIRED so the
        key works through the net-vm ProxyJump - restrict alone forbids the direct-tcpip
        channel), and `verify-required` (FIDO2 touch, sk- keys only). Port forwarding is
        still gated per-machine by the server's AllowTcpForwarding (net-vm "yes", internal
        VMs "no"), so re-enabling it on the key does not weaken non-jump machines.
        A non-hardware vaulted recovery key must use "restrict,pty,port-forwarding".
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = hasKeys || hasCA;
        message = "ghaf.security.ssh.release is enabled but neither authorizedKeys nor trustedUserCAKeys is set - the device would be reachable by no one.";
      }
      {
        assertion = !(config.ghaf.security.ssh.debug.enable or false);
        message = "Release SSH and debug SSH (ghaf.security.ssh.debug) must not both be enabled.";
      }
      {
        assertion = !(config.ghaf.reference.personalize.keys.enable or false);
        message = "Release SSH must not ship the hard-coded development authorizedSshKeys list (ghaf.reference.personalize.keys.enable).";
      }
      # Root login must be impossible in a release image, not merely absent
      # because no module happened to add a key. PermitRootLogin = "no" below is
      # the sshd-side half; these are the config-side half, and they catch any
      # future module that grants root a key without going through the dev-keys
      # module the assertion above covers.
      {
        assertion = config.users.users.root.openssh.authorizedKeys.keys == [ ];
        message = "Release SSH must not authorize root: root has authorized SSH keys. Dev keys belong to the debug profile only.";
      }
      {
        assertion = config.users.users.root.openssh.authorizedKeys.keyFiles == [ ];
        message = "Release SSH must not authorize root: root has authorized SSH key files.";
      }
    ];

    warnings = optional (hasCA && !hasKeys) ''
      ghaf.security.ssh.release uses a CA with no static authorizedKeys. If CA issuance is
      unavailable or a certificate expires, the device has no non-expiring break-glass login.
    '';

    services.openssh = {
      enable = true;
      # Static keys: system-level file only, never per-user ~/.ssh (srvos pattern).
      authorizedKeysFiles = lib.mkForce [ "/etc/ssh/authorized_keys.d/%u" ];
      settings = {
        AuthenticationMethods = "publickey";
        PubkeyAuthentication = true;
        TrustedUserCAKeys = mkIf hasCA "/etc/ssh/trusted_user_ca.pub";
        AuthorizedPrincipalsFile = mkIf hasCA "/etc/ssh/authorized_principals/%u";

        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
        AllowUsers = [ ghafUser ];

        X11Forwarding = false;
        UseDns = false;
        StreamLocalBindUnlink = true;
        AllowAgentForwarding = "no";
        AllowTcpForwarding = "no"; # net-vm overrides to "yes" (netvm-base)
        PermitTunnel = "no";
        Compression = "no";
        MaxAuthTries = 3;
        MaxSessions = 4;
        LoginGraceTime = 30;
        LogLevel = "VERBOSE";
        ClientAliveInterval = 300;
        ClientAliveCountMax = 2;
      };
    };

    environment.etc."ssh/authorized_keys.d/${ghafUser}" = mkIf hasKeys {
      text = concatMapStringsSep "\n" (k: "${cfg.authorizedKeysOptions} ${k}") cfg.authorizedKeys;
      mode = "0444";
    };
    environment.etc."ssh/trusted_user_ca.pub" = mkIf hasCA {
      text = concatStringsSep "\n" cfg.trustedUserCAKeys;
    };
    environment.etc."ssh/authorized_principals/${ghafUser}" = mkIf hasCA {
      text = concatStringsSep "\n" cfg.allowedPrincipals;
      mode = "0444";
    };

    # SYN-flood limiter (complementary to net-vm's fail2ban).
    ghaf.firewall.attack-mitigation.ssh.enable = true;
  };
}

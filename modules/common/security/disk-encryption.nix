{ lib, config, pkgs, utils, ... }: 
let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.ghaf.storage.encryption;
in
{
  options.ghaf.storage.encryption = {
    enable = mkEnableOption "Enable encryption of the data partition";
  };

  config = 
  let
    partConf = config.image.repart.partitions."50-persist".repartConfig;
    device = "/dev/disk/by-partuuid/${partConf.UUID}";
  in 
  mkIf cfg.enable {
    
    security.tpm2.enable = true;

    environment.systemPackages = [
      pkgs.cryptsetup
      pkgs.tpm2-tools
    ];

    environment.etc.crypttab.text = ''
      persist ${device} - tpm2-device=auto,luks,try-empty-password=true
    '';

    boot.plymouth.enable = lib.mkForce false;

    # POSSIBLE IMPROVEMENTS
    # - Disable service after first boot
    # - Integrate with plymouth (https://systemd.io/PASSWORD_AGENTS ?)
    systemd.services.luks-enroll-tpm = {
      wantedBy = [ "systemd-cryptsetup@persist.service" ];
      before = [ 
        "systemd-cryptsetup@persist.service" 
        "shutdown.target"
      ];
      after = [
        "systemd-tpm2-setup-early.service"
        "${utils.escapeSystemdPath device}.device"
        "nix-store.mount"
      ];
      wants = [
        "tpm2.target"
        "${utils.escapeSystemdPath device}.device"
        "nix-store.mount"
      ];
      script = ''
        if ${lib.getExe pkgs.cryptsetup} --dump-json-metadata luksDump ${device} | grep systemd-tpm2; then
          exit 0
        fi
        echo '========== Enrolling TPM for persist partition =========='
        systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=true ${device}
        echo '-- adding recovery key --'
        systemd-cryptenroll --recovery ${device}
        echo '-- removing initial empty passphrase --'
        systemd-cryptenroll --wipe-slot=empty ${device}
        read -p 'All done. Press Enter to continue'
      '';
      unitConfig.DefaultDependencies = "no";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StandardOutput = "tty";
        StandardInput = "tty";
        TTYPath = "/dev/tty1";
        TTYReset = "yes";
        TTYVHangup = "yes";
        TTYVTDisallocate = "yes";
      };
    };
  };
}
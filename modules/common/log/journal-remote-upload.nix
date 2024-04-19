{pkgs, ...}: let
  log-vm-ip-port = "192.168.101.66:19532";
in {
  users.users.systemd-journal-upload = {
    isSystemUser = true;
    group = "systemd-journal-upload";
  };
  users.groups.systemd-journal-upload = {};

  systemd.services.systemd-journal-upload = {
    enable = true;
    serviceConfig = {
      #ExecStart = "${pkgs.systemd}/lib/systemd/systemd-journal-upload --save-state -u http://${log-vm-ip-port}";
      ExecStart = "${pkgs.systemd}/lib/systemd/systemd-journal-upload -u http://${log-vm-ip-port}";
      User = "systemd-journal-upload";
    };

    wantedBy = ["multi-user.target"];
  };
}

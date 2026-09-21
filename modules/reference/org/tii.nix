# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# TII reference org configuration.A downstream project may supply its own org module.
{ config, lib, ... }:
let
  cfg = config.ghaf.reference.org.tii;
in
{
  _file = ./tii.nix;

  options.ghaf.reference.org.tii.enable = lib.mkEnableOption "TII reference org configuration";

  config = lib.mkIf cfg.enable {
    ghaf.org = {
      telemetry = {
        logging = {
          endpoint = "https://loki.ghaflogs.vedenemo.dev/loki/api/v1/push";
          serverName = "loki.ghaflogs.vedenemo.dev";
        };
        bugReport = {
          owner = "tiiuae";
          repo = "ghaf-bugreports";
        };
      };
      management.fleet.url = "https://fleetdm.vedenemo.dev";
      network.firewallRulesUrl = "https://raw.githubusercontent.com/tiiuae/ghaf-policies/deploy/vm-policies/firewall-rules/iptables.rules";

      # TII development AD test domain (formerly hardcoded in ad-users.nix). Realm,
      # KDC servers and LDAP URIs derive from domain and controllers (active-directory/options.nix).
      identity.activeDirectory.domains."ghaf-test.com" = {
        ad = {
          domain = "ghaf-test.com";
          controllers = [ "vm-ghaf-dev-dc.ghaf-test.com" ];
        };
        dnsProvider = {
          name = "vm-ghaf-dev-dc.ghaf-test.com";
          ipAddress = "10.52.33.4";
        };
        ldap = {
          schema = "ad";
          # TII's AD publishes POSIX attributes; map them RFC2307-style
          # (idMapping stays false, the shared type's default).
          extraConfig = ''
            # RFC2307 User and group attribute mappings
            ldap_user_name = uid
            ldap_user_uid_number = uidNumber
            ldap_user_gid_number = gidNumber
            ldap_user_home_directory = homeDirectory
            ldap_user_shell = loginShell
          '';
        };
      };

      # Release images admit no org SSH keys yet; an empty list means
      # exactly that, and release test keys land here when TII issues them.
      identity.ssh.releaseKeys = [ ];

      # Development SSH key roster, admitted on debug images only. Note that this implies
      # root access across all machines with a debug image, as do the default credentials.
      identity.ssh.debugKeys = [
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIA/pwHnzGNM+ZU4lANGROTRe2ZHbes7cnZn72Oeun/MCAAAABHNzaDo= brian@arcadia"
        "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIEJ9ewKwo5FLj6zE30KnTn8+nw7aKdei9SeTwaAeRdJDAAAABHNzaDo= brian@minerva"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILu6O3swRVWAjP7J8iYGT6st7NAa+o/XaemokmtKdpGa brian@builder"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICKm9NtS/ZmrxQhY/pbRlX+9O1VaBEd8D9vojDtvS0Ru juliuskoskela@vega"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM3w7NzqMuF+OAiIcYWyP9+J3kwvYMKQ+QeY9J8QjAXm shamma-alblooshi@tii.ae"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB/iv9RWMN6D9zmEU85XkaU8fAWJreWkv3znan87uqTW humaid@tahr"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGOifxDCESZZouWLpoCWGXEYOVbMz53vrXTi9RQe4Bu5 hazaa@nixos"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICwsW+YJw6ukhoWPEBLN93EFiGhN7H2VJn5yZcKId56W mb@mmm"
        "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBCsjXKHCkpQT4LhWIdT0vDM/E/3tw/4KHTQcdJhyqPSH0FnwC8mfP2N9oHYFa2isw538kArd5ZMo5DD1ujL5dLk= joerg@turingmachine"
        "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBLMlGNda7bilB0+3aMeJSFcB17auBPV0WhW60WlGZsQRF50Z/OgIHAA0/8HaxPmpIOLHv8JO3dCsj+OY1iS4FNo= joerg@turingmachine"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIstCgKDX1vVWI8MgdVwsEMhju6DQJubi3V0ziLcU/2h vunny.sodhi@unikie.com"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINfyjcPGIRHEtXZgoF7wImA5gEY6ytIfkBeipz4lwnj6 Ganga.Ram@tii.ae"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEA7p7hHPvPT6uTU44Nb/p9/DT9mOi8mpqNllnpfawDE tanel@nixos"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIwGPH/oOrD1g15uiPV4gBKGk7f8ZBSyMEaptKOVs3NG jaroslawkurowski@TII-JaroslawKurowski"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHu4r7nCQ6A26HsE4+wIupvXAfVQHgBGXv0+epCho2/m rodrigo.pino@tii.ae"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGll9sWYdGc2xi9oQ25TEcI1D3T4n8MMXoMT+lJdE/KC milla@nixos"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGJSuGlmQ/iMu7JGL7L4jVT3d+o4MiOsuh0e1ZVkBUKq gayathri@tii.ae"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINlIpJ9Q1oW1KiFBa12N5K/ecGVeGSBbcD8M9ZjA0TYe kajus.naujokaitis@unikie.com"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPE/CgI8MXyHiiUyt7BXWjQG1pb25b4N3als/dKKPZyD samuli@nixos"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJpTkKsWyFQxWKwL22fghfJnLaOhUtZLlF9h2gdWcoJz everton.dematos@tii.ae"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHkq2GqA7XfW4JN8kiDLjaYf8j2zOsw1DABA7wLmk1qN janne.pirskanen@tii.ae"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFGzGy5vw2+bdwcGpQ7gwyiNvZ1HlolSHTP3tEUpzpoC emrah.billur@unikie.com"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIk35lv+XqSyMOF+mChNLGnc0/vCVrNicLg5ZGMwXsCe eyad.shaklab@tii.ae"

        # For ghaf-installer automated testing:
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAolaKCuIUBQSBFGFZI1taNX+JTAr8edqUts7A6k2Kv7"
      ];
    };
  };
}

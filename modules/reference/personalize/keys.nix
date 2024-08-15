# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.reference.personalize.keys;
  inherit (lib)
    mkEnableOption
    mkIf
    concatStrings
    mkForce
    ;

  authorizedYubikeys = [
    # Yubikey public keys for testing team, enabled only in debug mode
    #1
    "ghaf:3HbulvTWYKkZEX6VaFX/EWLUp2FwHMUQQvhi8dGjOd1U+5gUxarLyqGcVzeAte5wpvTGkcRckcfN3Ce9iK0smA==,/j1T0Z4vNv72218WkRemtSMaqv4ysw6Oa6Db8KnLFczv5DxzBhHj+e3kinNX89wvwJWe9XlxPQqE54jmzi227w==,es256,+presence"
    #2
    "ghaf:fkBGKisgW8B1AAQDe6l6QWMbvaM3vfIahYwnlWcyKoI0aM62hPBL3l1x5IUyQy41kpe1+nbR4K6KX43utDz7kA==,nEVF0RHTNpzRvem1Ng3KnHhlXXj28tvQvbA+YF39p6fzJpq0t9czGb85kmPms9pGquQiOFTDrEURUmdC6PA8Ng==,es256,+presence"
    #3
    "ghaf:zQlVob4+w3DcvtN6BPjBPaEssJ3PYNSQVlWLk/Uq/Qlbqk9D0IjPjZDm5XwTuKhropVR1hVA4XdZKsSs9BlUEQ==,G3qgBAhmCwANuCdCZzo68QLFFQ4aud/a3X5r1m8UeUpMh5BlDHrHAR0sE0H/d4v7RiScex2TZaHrgYV507BFRA==,es256,+presence"
    #4
    "ghaf:QaA1B4u1GzLt+HSwXpMxmdCOKiBN4WZSUAuEXZahNSpcv8xiYagp0ntVsl8TOx4K+sKls3gTn37Uso/dmncwdA==,mr0Nhwkok7VLUtkBMryOA0lZghU23SCYtU3CZeW5P4WVtnPax3N/6GkfuAv6Zw5ejC4BDvov3oKHTQT/F8eYqA==,es256,+presence"
  ];

  authorizedSshKeys = [
    # Add your SSH Public Keys here
    # NOTE: adding your pub ssh key here will make accessing and "nixos-rebuild switching" development mode
    # builds easy but still secure. Given that you protect your private keys. Do not share your keypairs across hosts.
    #
    # Shared authorized keys access poses a minor risk for developers in the same network (e.g. office) cross-accessing
    # each others development devices if:
    # - the ip addresses from dhcp change between the developers without the noticing AND
    # - you ignore the server fingerprint checks
    # You have been helped and you have been warned.
    "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIA/pwHnzGNM+ZU4lANGROTRe2ZHbes7cnZn72Oeun/MCAAAABHNzaDo= brian@arcadia"
    "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIEJ9ewKwo5FLj6zE30KnTn8+nw7aKdei9SeTwaAeRdJDAAAABHNzaDo= brian@minerva"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILu6O3swRVWAjP7J8iYGT6st7NAa+o/XaemokmtKdpGa brian@builder"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDdNDuKwAsAff4iFRfujo77W4cyAbfQHjHP57h/7tJde ville.ilvonen@unikie.com"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICKm9NtS/ZmrxQhY/pbRlX+9O1VaBEd8D9vojDtvS0Ru juliuskoskela@vega"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDJau0tg0qHhqFVarjNOJLi+ekSZNNqxal4iRD/pwM5W tervis@tervis-thinkpad"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAHVXc4s7e8j1uFsgHPBzpWvSI/hk5Zf6Btuj79D4hf3 tervis@tervis-servu"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM3w7NzqMuF+OAiIcYWyP9+J3kwvYMKQ+QeY9J8QjAXm shamma-alblooshi@tii.ae"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB/iv9RWMN6D9zmEU85XkaU8fAWJreWkv3znan87uqTW humaid@tahr"

    # For ghaf-installer automated testing:
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAolaKCuIUBQSBFGFZI1taNX+JTAr8edqUts7A6k2Kv7"
  ];
in
{
  options.ghaf.reference.personalize.keys = {
    enable = mkEnableOption "Enable personalization of keys for dev team";
  };

  config = mkIf cfg.enable {
    users.users.root.openssh.authorizedKeys.keys = authorizedSshKeys;
    users.users.${config.ghaf.users.accounts.user}.openssh.authorizedKeys.keys = authorizedSshKeys;
    ghaf.services.yubikey.u2fKeys = mkForce (concatStrings authorizedYubikeys);
  };
}

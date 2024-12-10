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

  inherit ((import ./authorizedSshKeys.nix)) authorizedSshKeys;
in
{
  options.ghaf.reference.personalize.keys = {
    enable = mkEnableOption "Enable personalization of keys for dev team";
  };

  config = mkIf cfg.enable {
    users.users.root.openssh.authorizedKeys.keys = authorizedSshKeys;
    users.users.${config.ghaf.users.admin.name}.openssh.authorizedKeys.keys = authorizedSshKeys;
    ghaf.services.yubikey.u2fKeys = mkForce (concatStrings authorizedYubikeys);
  };
}

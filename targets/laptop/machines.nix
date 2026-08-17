# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# The laptop machine table.
#
# HARD RULE: data only. No `ghaf.*`, no `lib` calls, no conditionals, no inline
# modules. Anything a machine needs beyond the fields below belongs in
# modules/reference/hardware/. Enforced by checks.laptop-table-is-data.
#
# Fields:
#   hardware   suffix of nixosModules.hardware-*        (required)
#   variants   subset of [ "debug" "release" ]          (required)
#   product    reference profile to enable              (default "mvp-user-trial")
#   axes       names from ./axes.nix, expanded as a     (default [ ])
#              power set into one target per subset
#   sysupdate  also emit an A/B update image            (default false)
{
  # keep-sorted start block=yes newline_separated=yes
  alienware-m18-R2 = {
    hardware = "alienware-m18-r2";
    variants = [
      "debug"
      "release"
    ];
  };

  dell-latitude-7230 = {
    hardware = "dell-latitude-7230";
    variants = [
      "debug"
      "release"
    ];
  };

  dell-latitude-7330 = {
    hardware = "dell-latitude-7330";
    variants = [
      "debug"
      "release"
    ];
  };

  demo-tower-mk1 = {
    hardware = "demo-tower-mk1";
    variants = [
      "debug"
      "release"
    ];
  };

  intel-laptop = {
    hardware = "intel-laptop";
    variants = [
      "debug"
      "release"
    ];
    axes = [
      "low-mem"
      "storeDisk"
    ];
  };

  lenovo-t14-amd-gen5 = {
    hardware = "lenovo-t14-amd-gen5";
    variants = [
      "debug"
      "release"
    ];
  };

  lenovo-x1-2-in-1-gen9 = {
    hardware = "lenovo-x1-2-in-1-gen9";
    variants = [
      "debug"
      "release"
    ];
  };

  lenovo-x1-carbon-gen10 = {
    hardware = "lenovo-x1-carbon-gen10";
    variants = [
      "debug"
      "release"
    ];
  };

  lenovo-x1-carbon-gen11 = {
    hardware = "lenovo-x1-carbon-gen11";
    variants = [
      "debug"
      "release"
    ];
    sysupdate = true;
  };

  lenovo-x1-carbon-gen12 = {
    hardware = "lenovo-x1-carbon-gen12";
    variants = [
      "debug"
      "release"
    ];
  };

  lenovo-x1-carbon-gen13 = {
    hardware = "lenovo-x1-carbon-gen13";
    variants = [
      "debug"
      "release"
    ];
  };

  # Same board as gen11, different application set.
  lenovo-x1-extras = {
    hardware = "lenovo-x1-carbon-gen11";
    product = "mvp-user-trial-extras";
    variants = [
      "debug"
      "release"
    ];
  };

  system76-darp11-b = {
    hardware = "system76-darp11-b";
    variants = [
      "debug"
      "release"
    ];
    axes = [ "storeDisk" ];
  };

  tower-5080 = {
    hardware = "tower-5080";
    variants = [
      "debug"
      "release"
    ];
  };
  # keep-sorted end
}

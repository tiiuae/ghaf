<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Labwc Desktop Environment

[Labwc](https://labwc.github.io/) is a configurable and lightweight wlroots-based Wayland-compatible desktop environment.
To use Labwc as your default desktop environment, add it as a module to Ghaf:

* change the configuration option `profiles.graphics.compositor = "labwc"`
or
* uncomment the corresponding line in [guivm.nix](../modules/virtualization/microvm/guivm.nix) file.


The basis of the labwc configuration is the set of following files: `rc.xml`, `menu.xml`, `autostart`, and `environment`. These files can be edited by substituting in the Labwc overlay `overlays/custom-packages/labwc/default.nix`.


## Window Border Coloring

The border color concept illustrates the application trustworthiness in a user-friendly manner. The color shows the application's security level and allows avoiding user's mistakes. The same approach can be found in other projects, for example, [QubeOS](https://www.qubes-os.org/doc/getting-started/#color--security).

Ghaf uses patched Labwc which makes it possible to change the border color for the chosen application. The implementation is based on window rules by substituting the server decoration colors (`serverDecoration` = `yes`). The `borderColor` property is responsible for the frame color.

> **TIP:** According to the labwc specification, the **identifier** parameter is case-sensitive and relates to app_id for native Wayland windows and WM_CLASS for XWayland clients.

For example:
```
<windowRules>
  <windowRule identifier="Foot" borderColor="#00FFFF" serverDecoration="yes" skipTaskbar="yes"  />
  <windowRule identifier="firefox" borderColor="#FF0000" serverDecoration="yes" skipTaskbar="yes"  />
</windowRules>
```

![Foot Terminal with Aqua Colored Frame](../img/colored_foot_frame.png)

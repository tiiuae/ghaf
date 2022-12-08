
final: prev: {
    spectrum-rootfs = prev.spectrum-rootfs.overrideAttrs (old: {
        # TODO move this feature to the future "development" release.
        # This patch allows to use serial console through USB interface of NUC
        # device.
        patches = [ ./patches/0001-Open-USB-serial-terminal-at-boot.patch ];
    });
    spectrum-live = prev.spectrum-live.overrideAttrs (old: {
        ROOT_FS = final.spectrum-rootfs;
    });
}

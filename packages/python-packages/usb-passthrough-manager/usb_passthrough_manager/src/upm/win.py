# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
import threading
from typing import List, Optional
from upm.api_client import APIClient
import gi

from upm.logger import logger

gi.require_version("Gtk", "4.0")
gi.require_version("GLib", "2.0")

from gi.repository import Gtk, Gio


SELECT_LABEL = "Select"


class WinGenerator(Gtk.ApplicationWindow):
    def __init__(
        self,
        app: Gtk.Application,
        apiclient,
        devices,
        title: str = "Device Bridge",
    ):
        super().__init__(application=app, title=title)
        self.devices = {}
        for dev in devices:
            if "device_node" in dev:
                self.devices[dev.get("device_node")] = dev
        self.apiclient = apiclient
        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.set_child(root)

        content_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        content_box.set_margin_top(8)
        content_box.set_margin_bottom(8)
        content_box.set_margin_start(8)
        content_box.set_margin_end(8)
        content_box.set_hexpand(True)
        content_box.set_vexpand(True)
        root.append(content_box)

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scroller.set_hexpand(True)
        scroller.set_vexpand(True)
        content_box.append(scroller)
        self.inner = Gtk.FlowBox()
        self.inner.set_selection_mode(Gtk.SelectionMode.NONE)
        self.inner.set_valign(Gtk.Align.START)
        self.inner.set_halign(Gtk.Align.FILL)
        self.inner.set_column_spacing(8)
        self.inner.set_row_spacing(8)
        self.inner.set_homogeneous(False)
        self.inner.set_min_children_per_line(2)
        self.inner.set_max_children_per_line(2)
        scroller.set_child(self.inner)

        self.action_bar = Gtk.ActionBar()
        root.append(self.action_bar)

        self.action_bar.pack_start(Gtk.Box(hexpand=True))
        self.blocks = {}

    def _add_close_btn(self):
        self.close_btn = Gtk.Button(label="Close")
        self.close_btn.connect("clicked", lambda *_: self.close())
        self.action_bar.pack_end(self.close_btn)
        self.connect("close-request", self._on_close_request)

    def _add_refresh_btn(self):
        self.refresh_btn = Gtk.Button(label="Refresh")
        self.refresh_btn.set_tooltip_text("Refresh status from JSON.")
        self.refresh_btn.connect("clicked", self._on_refresh_clicked)
        self.action_bar.pack_end(self.refresh_btn)

    def show_notification(self):
        self.set_default_size(300, 200)
        self._add_close_btn()
        self._load_ui()

    def show_app_window(self):
        self.set_default_size(860, 380)
        self._add_refresh_btn()
        self._add_close_btn()
        self._load_ui()

    def _clear_blocks_ui(self) -> None:
        for info in list(self.blocks.values()):
            container = info.get("container")
            if container is not None and container.get_parent() is not None:
                self.inner.remove(container)
        self.blocks.clear()

    def _make_dropdown(
        self, device_id: str, items: List[str], selected: Optional[str]
    ) -> Gtk.DropDown:
        model = Gtk.StringList.new([SELECT_LABEL] + items)
        dropdown = Gtk.DropDown.new(model=model, expression=None)
        dropdown.set_hexpand(False)
        if selected and selected in items:
            dropdown.set_selected(items.index(selected) + 1)
        else:
            dropdown.set_selected(0)
        dropdown.connect("notify::selected", self._on_dropdown_changed, device_id)
        return dropdown

    def _add_block_ui(
        self,
        device_id: str,
        product: str,
        targets: List[str],
        selected: Optional[str],
    ) -> None:
        frame = Gtk.Frame()
        frame.add_css_class("card")
        frame.set_hexpand(True)
        frame.set_vexpand(False)

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        vbox.set_margin_top(12)
        vbox.set_margin_bottom(12)
        vbox.set_margin_start(12)
        vbox.set_margin_end(12)
        frame.set_child(vbox)

        lbl = Gtk.Label()
        lbl.set_use_markup(True)
        lbl.set_selectable(True)
        lbl.set_xalign(0.0)
        lbl.set_hexpand(True)
        logger.info(f"Markup: {product}")
        lbl.set_markup(f"{product}:")
        vbox.append(lbl)

        dropdown = self._make_dropdown(device_id, targets, selected)
        vbox.append(dropdown)

        self.inner.append(frame)

        self.blocks[device_id] = {
            "container": frame,
            "label": lbl,
            "dropdown": dropdown,
        }

    def _load_ui(self):
        self._clear_blocks_ui()
        for dev_id, dev in self.devices.items():
            permitted = dev.get("allowed_vms", [])

            if len(permitted) < 2:
                continue
            product = dev.get("product_name")
            selected = dev.get("vm")
            self._add_block_ui(dev_id, product, permitted, selected)

    def _request_passthrough(self, device_id: str, new_vm: str) -> bool:
        device = self.devices.get(device_id, {})
        current = device.get("vm", "")
        if current != "":
            response = self.apiclient.usb_detach(device_id)
        if new_vm.lower() != "eject":
            response = self.apiclient.usb_attach(device_id, new_vm)
            if (
                response.get("event", "") == "usb_attached"
                or response.get("result", "") == "ok"
            ):
                self.devices[device_id]["vm"] = new_vm
            else:
                logger.error(f"Failed to attach device! Response: {response}")
                return False
            return True

    def _on_dropdown_changed(
        self, dropdown: Gtk.DropDown, _pspec, device_id: str
    ) -> None:
        idx = dropdown.get_selected()
        if idx < 0:
            return
        model = dropdown.get_model()
        text = model.get_string(idx)
        if text is None or text == SELECT_LABEL:
            return
        status = self._request_passthrough(device_id, text)
        if not status:
            self._show_error_dialog(
                title="Error", message="Failed to request passthrough."
            )

    def _on_refresh_clicked(self, _btn: Gtk.Button) -> None:
        response = self.apiclient.usb_list()
        if response.get("result") == "ok":
            devlist = response.get("usb_devices", [])
            self.devices.clear()
            for dev in devlist:
                if "device_node" in dev:
                    self.devices[dev.get("device_node")] = dev
            self._load_ui()

    def _show_error_dialog(self, title: str, message: str) -> bool:
        dlg = Gtk.MessageDialog(
            transient_for=self,
            modal=True,
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.CLOSE,
            text=title,
            secondary_text=message,
        )
        dlg.connect("response", lambda d, _r: d.destroy())
        dlg.present()
        return False

    def _on_close_request(self, *_args) -> bool:
        return False


class USBDeviceMap(Gtk.Application):
    def __init__(self, server_port=2000):
        super().__init__(
            application_id="ghaf.usb-device.map", flags=Gio.ApplicationFlags.FLAGS_NONE
        )
        self.server_port = server_port
        self._win: Optional[WinGenerator] = None

    def do_activate(self):
        if not self._win:
            apiclient = APIClient(port=self.server_port)
            apiclient.connect()
            devices = apiclient.usb_list()
            if devices.get("result") == "ok":
                self._win = WinGenerator(
                    self,
                    apiclient=apiclient,
                    devices=devices.get("usb_devices", []),
                    title="USB Device Map",
                )
                self._win.show_app_window()
        self._win.present()


class Notification(Gtk.Application):
    def __init__(self, device, apiclient):
        super().__init__(
            application_id="ghaf.usbdevice.notificiation",
            flags=Gio.ApplicationFlags.FLAGS_NONE,
        )
        self.device = device
        logger.info(f"Notifiation:{device}")
        self.apiclient = apiclient
        self._win: Optional[WinGenerator] = None

    def do_activate(self):
        if not self._win:
            logger.info(f"do_activate:{self.device}")
            self._win = WinGenerator(
                self,
                apiclient=self.apiclient,
                devices=[self.device],
                title="Device Notification!",
            )
            self._win.show_notification()
        self._win.present()


class USBDeviceNotification:
    def __init__(self, server_port=2000):
        th, apiclient = APIClient.recv_notifications(
            callback=self.notify_user, port=server_port, cid=2, reconnect_delay=3
        )
        self.apiclient = apiclient
        th.join()

    def notify_user(self, msg):
        logger.info(f"New device notification: {msg}")
        dev = msg.get("usb_device", {})
        allowed = msg.get("allowed_vms", [])
        logger.info(f"New device notification: {dev} --- {allowed} -- {len(allowed)}")
        if len(allowed) < 2:
            return
        dev["allowed_vms"] = allowed
        th = threading.Thread(target=self.show_notif_window, args=(dev, self.apiclient))
        th.start()
        th.join()

    def show_notif_window(self, device, apiclient):
        notif = Notification(device=device, apiclient=apiclient)
        raise SystemExit(notif.run(None))

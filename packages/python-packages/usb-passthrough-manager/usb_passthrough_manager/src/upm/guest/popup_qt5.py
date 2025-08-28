# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

import logging
import sys
import threading
from typing import Any

from PyQt5.QtCore import Qt
from PyQt5.QtWidgets import (
    QApplication,
    QComboBox,
    QFrame,
    QHBoxLayout,
    QLabel,
    QMessageBox,
    QPushButton,
    QScrollArea,
    QVBoxLayout,
    QWidget,
)

logger = logging.getLogger("upm")

SELECT_LABEL = "Select"


def popup_thread_func(
    passthrough_handler,
    device_id: str = "",
    vendor: str = "",
    product: str = "",
    permitted_vms: list[str] = [],
    current_vm: str = "",
):
    app = QApplication(sys.argv)
    popup = NewDevicePopup(
        passthrough_handler, device_id, vendor, product, permitted_vms, current_vm
    )
    popup.show()
    sys.exit(app.exec_())


def show_new_device_popup_async(
    passthrough_handler,
    device_id: str = "",
    vendor: str = "",
    product: str = "",
    permitted_vms: list[str] = [],
    current_vm: str = "",
):
    th = threading.Thread(
        target=popup_thread_func,
        args=(
            passthrough_handler,
            device_id,
            vendor,
            product,
            permitted_vms,
            current_vm,
        ),
    )
    th.start()
    th.join()


class NewDevicePopup(QWidget):
    def __init__(
        self,
        passthrough_handler,
        device_id: str = "",
        vendor: str = "",
        product: str = "",
        permitted_vms: list[str] = [],
        current_vm: str = "",
        width: int = 320,
        height: int = 220,
    ):
        super().__init__()
        self.setWindowTitle("New USB Device")
        self.resize(width, height)

        self.blocks: dict[str, dict[str, Any]] = {}

        # Main layout
        root = QVBoxLayout(self)
        self.scroll = QScrollArea()
        self.scroll.setWidgetResizable(True)
        self.inner = QWidget()
        self.devices_layout = QVBoxLayout(self.inner)
        self.devices_layout.setSpacing(12)
        self.devices_layout.addStretch(1)
        self.scroll.setWidget(self.inner)
        root.addWidget(self.scroll)

        # Bottom buttons
        btn_row = QHBoxLayout()
        btn_row.addStretch(1)
        self.close_btn = QPushButton("Close")
        self.close_btn.clicked.connect(self.close)
        btn_row.addWidget(self.close_btn)
        root.addLayout(btn_row)
        self.device_id = device_id
        self.vendor = vendor
        self.product = product
        self.permitted_vms = permitted_vms
        self.current_vm = current_vm
        self.passthrough_handler = passthrough_handler
        self.draw()

    def _clear_blocks(self):
        for info in self.blocks.values():
            w = info.get("container")
            if w:
                w.setParent(None)
                w.deleteLater()
        self.blocks.clear()

    def _make_combo(
        self, device_id: str, items: list[str], selected: str | None
    ) -> QComboBox:
        combo = QComboBox()
        combo.setEditable(False)
        all_items = [SELECT_LABEL, *items]
        combo.addItems(all_items)

        fm = combo.fontMetrics()
        longest_px = max((fm.horizontalAdvance(s) for s in all_items), default=60)
        combo.setFixedWidth(longest_px + 60)
        combo.view().setMinimumWidth(longest_px + 60)
        idx = (
            0 if not selected or selected not in items else (items.index(selected) + 1)
        )
        combo.setCurrentIndex(idx)
        combo.currentIndexChanged.connect(
            lambda _i, d=device_id: self.on_combo_changed(d)
        )

        return combo

    def _add_block(
        self,
        device_id: str,
        vendor: str,
        product: str,
        targets: list[str],
        selected: str | None,
    ):
        container = QFrame()
        container.setFrameShape(QFrame.NoFrame)
        v = QVBoxLayout(container)
        v.setSpacing(6)

        lbl = QLabel()
        lbl.setTextFormat(Qt.RichText)
        lbl.setTextInteractionFlags(Qt.TextSelectableByMouse)
        lbl.setText(f"<b>{self.vendor} ({self.product}) [{self.device_id}]:</b>")
        v.addWidget(lbl)

        combo = self._make_combo(device_id, targets, selected)
        v.addWidget(combo)

        self.devices_layout.insertWidget(self.devices_layout.count() - 1, container)
        self.blocks[device_id] = {"container": container, "label": lbl, "combo": combo}

    def draw(self):
        self._clear_blocks()
        self._add_block(
            self.device_id,
            self.vendor,
            self.product,
            self.permitted_vms,
            self.current_vm,
        )

    def on_combo_changed(self, device_id: str):
        info = self.blocks.get(device_id)
        if not info:
            return
        combo: QComboBox = info["combo"]
        new_vm = combo.currentText()
        if new_vm == SELECT_LABEL:
            return
        if not self.passthrough_handler(device_id, new_vm):
            QMessageBox.critical(
                self, "Send error", "Failed to send passthrough request!"
            )

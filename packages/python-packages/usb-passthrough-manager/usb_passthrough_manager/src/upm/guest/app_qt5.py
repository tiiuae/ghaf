# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

import json
import logging
from pathlib import Path
from typing import Any

from PyQt5.QtCore import Qt
from PyQt5.QtWidgets import (
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


def device_title_html(device_id: str, vendor: str, product: str) -> str:
    # Bold: Vendor (Product) [vid:pid]:
    v = vendor or ""
    p = product or ""
    return f"<b>{v} ({p}) [{device_id}]:</b>"


def _read_schema_once(path: Path) -> dict[str, Any]:
    try:
        logger.debug(f"schema file: {path}")
        with open(path) as f:
            doc = json.load(f) or {}
    except Exception as e:
        logger.error(f"Failed to read schema file: {e}")
        return {}

    if not isinstance(doc, dict):
        return {}

    return doc


class App(QWidget):
    def __init__(
        self,
        data_dir: str,
        combo_width: int | None = 100,
        popup_width: int | None = None,
    ):
        super().__init__()
        self.setWindowTitle("Device Router")
        self.resize(760, 560)

        self.file_path = Path(data_dir) / "usb_db.json"
        self.fifo_path = Path(data_dir) / "app_request.fifo"
        self.combo_width = combo_width
        self.popup_width = popup_width
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
        self.refresh_btn = QPushButton("Refresh")
        self.refresh_btn.setToolTip("Re-read the JSON file and update the UI.")
        self.refresh_btn.clicked.connect(self.reload_from_file)
        self.close_btn = QPushButton("Close")
        self.close_btn.clicked.connect(self.close)
        btn_row.addWidget(self.refresh_btn)
        btn_row.addWidget(self.close_btn)
        root.addLayout(btn_row)

        # Initial load
        self.reload_from_file()

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

        if self.combo_width:
            combo.setFixedWidth(self.combo_width)
        else:
            combo.setSizeAdjustPolicy(QComboBox.AdjustToContents)
            combo.setMinimumContentsLength(max((len(s) for s in all_items), default=8))

        if self.popup_width:
            combo.view().setMinimumWidth(self.popup_width)
        else:
            fm = combo.fontMetrics()
            longest_px = max((fm.horizontalAdvance(s) for s in all_items), default=80)
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
        lbl.setText(device_title_html(device_id, vendor, product))
        v.addWidget(lbl)

        combo = self._make_combo(device_id, targets, selected)
        v.addWidget(combo)

        self.devices_layout.insertWidget(self.devices_layout.count() - 1, container)
        self.blocks[device_id] = {"container": container, "label": lbl, "combo": combo}

    def reload_from_file(self):
        doc = _read_schema_once(self.file_path)
        self._clear_blocks()

        for dev_id, meta in doc.items():
            permitted = list(meta.get("permitted-vms", []))
            vendor = meta.get("vendor") or ""
            product = meta.get("product") or ""
            selected = meta.get("current-vm") or ""
            self._add_block(dev_id, vendor, product, permitted, selected)

    def request_passthrough(self, device_id: str, new_vm: str) -> bool:
        request = f"{device_id}->{new_vm}\n"
        with open(self.fifo_path, "w", encoding="utf-8", buffering=1) as f:
            try:
                f.write(request)
                return True
            except Exception as e:
                logger.error(f"Failed to send passthrough request: {e}")
                return False
        return False

    def on_combo_changed(self, device_id: str):
        info = self.blocks.get(device_id)
        if not info:
            return
        combo: QComboBox = info["combo"]
        new_vm = combo.currentText()
        if new_vm == SELECT_LABEL:
            return
        if not self.request_passthrough(device_id, new_vm):
            QMessageBox.critical(
                self, "Send error", "Failed to send passthrough request!"
            )

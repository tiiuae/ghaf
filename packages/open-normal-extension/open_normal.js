// SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

chrome.contextMenus.create({
  id: "openNormal",
  title: "Open in normal browser",
  contexts: ["link"],
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId === "openNormal") {
    sendNativeMessage(info.linkUrl);
  }
});

function sendNativeMessage(linkUrl) {
  chrome.runtime.sendNativeMessage(
    "fi.ssrc.open_normal",
    { URL: linkUrl },
    (response) => {
      if (chrome.runtime.lastError) {
        console.error(chrome.runtime.lastError);
      } else {
        console.log("open_normal:", response);
      }
    },
  );
}

// SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

// Add pop-up menu item for links
chrome.contextMenus.create({
  id: "openNormalLink",
  title: "Open link in normal browser",
  contexts: ["link"], // Register for links
});

// Add pop-up menu item for page
chrome.contextMenus.create({
  id: "openNormalPage",
  title: "Open page in normal browser",
  contexts: ["page"], // Register for the page and the address-bar
});

// Listen for context menu click events
chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId === "openNormalLink") {
    sendNativeMessage(info.linkUrl); // Open with link URL
  } else if (info.menuItemId === "openNormalPage") {
    sendNativeMessage(tab.url); // Open with address-bar URL of the tab
  }
});

// Listen for the extension icon click events
chrome.action.onClicked.addListener((tab) => {
  sendNativeMessage(tab.url);
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

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
  // Input validation: ensure URL is properly formatted and not malicious
  if (!linkUrl || typeof linkUrl !== "string") {
    console.error("Invalid URL provided");
    return;
  }

  // Basic URL validation - allow http, https, and file protocols
  const urlPattern = /^(https?|file):\/\/.+/i;
  if (!urlPattern.test(linkUrl)) {
    console.error("URL must use http, https, or file protocol");
    return;
  }

  // Prevent javascript: and data: URLs that could be used for XSS
  const dangerousProtocols = /^(javascript|data|vbscript):/i;
  if (dangerousProtocols.test(linkUrl)) {
    console.error("Dangerous URL protocol detected");
    return;
  }

  chrome.runtime.sendNativeMessage(
    "fi.ssrc.open_normal",
    { URL: linkUrl },
    (response) => {
      if (chrome.runtime.lastError) {
        console.error(
          "Native messaging error:",
          chrome.runtime.lastError.message,
        );
      } else {
        console.log("open_normal response:", response);
      }
    },
  );
}

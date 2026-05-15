// Service worker: registers the context menu and opens the save popup on click.

const MENU_ID = "bookmark-server-save";

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: MENU_ID,
    title: "Save to Bookmark Server",
    contexts: ["page", "link"],
  });
});

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId !== MENU_ID) return;

  // Try the official "open the action popup" API first. If the browser
  // version is too old or refuses (e.g. blocked outside a user gesture
  // chain), fall back to opening the popup in a tab.
  try {
    await chrome.action.openPopup();
  } catch (_err) {
    chrome.tabs.create({ url: chrome.runtime.getURL("popup/popup.html") });
  }
});

// Service worker: registers the context menu, opens the save popup on
// click, and keeps a tab-scoped "already saved" badge on the toolbar
// icon in sync with the active tab's URL.

const MENU_ID = "tsundoku-save";
const BADGE_TEXT = "✓";
const BADGE_COLOR = "#22c55e";

// Short-lived in-memory cache: URL -> Promise<bool>. Avoids spamming
// /api/find_bookmark when the user flips between the same few tabs.
// Service workers can be torn down at any time so this is a best-effort
// optimization, not correctness.
const savedCache = new Map();
const CACHE_TTL_MS = 60_000;

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: MENU_ID,
    title: "Save to Tsundoku",
    contexts: ["page", "link"],
  });
});

chrome.contextMenus.onClicked.addListener(async (info, _tab) => {
  if (info.menuItemId !== MENU_ID) return;

  try {
    await chrome.action.openPopup();
  } catch (_err) {
    chrome.tabs.create({ url: chrome.runtime.getURL("popup/popup.html") });
  }
});

// Badge sync: when the active tab changes or its URL updates, ask the
// server whether the URL is saved and toggle the badge.

chrome.tabs.onActivated.addListener(({ tabId }) => {
  chrome.tabs.get(tabId, (tab) => {
    if (chrome.runtime.lastError || !tab) return;
    refreshBadge(tabId, tab.url);
  });
});

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  // Re-check whenever the URL changes or the page finishes loading.
  if (changeInfo.url || changeInfo.status === "complete") {
    refreshBadge(tabId, tab.url);
  }
});

chrome.tabs.onRemoved.addListener((tabId) => {
  // Best-effort: per-tab badges are cleared automatically when the tab
  // closes, but clearing the cache entry isn't useful unless many tabs
  // shared one URL — leave the cache alone.
  void tabId;
});

async function refreshBadge(tabId, url) {
  if (!url || !/^https?:\/\//i.test(url)) {
    clearBadge(tabId);
    return;
  }

  try {
    const saved = await isSaved(url);
    if (saved) {
      chrome.action.setBadgeBackgroundColor({ color: BADGE_COLOR, tabId });
      chrome.action.setBadgeText({ text: BADGE_TEXT, tabId });
    } else {
      clearBadge(tabId);
    }
  } catch (_err) {
    clearBadge(tabId);
  }
}

function clearBadge(tabId) {
  try {
    chrome.action.setBadgeText({ text: "", tabId });
  } catch (_err) {
    /* tab might be gone */
  }
}

async function isSaved(url) {
  const cached = savedCache.get(url);
  if (cached && Date.now() - cached.at < CACHE_TTL_MS) return cached.value;

  const promise = checkSaved(url);
  // Cache the in-flight promise too so concurrent tab switches collapse.
  savedCache.set(url, { value: promise, at: Date.now() });
  const value = await promise;
  savedCache.set(url, { value, at: Date.now() });
  return value;
}

async function checkSaved(url) {
  const { serverUrl, token } = await getConfig();
  if (!serverUrl || !token) return false;

  const base = serverUrl.replace(/\/$/, "");
  const target =
    base + "/api/find_bookmark?url=" + encodeURIComponent(url);

  const response = await fetch(target, {
    headers: { Authorization: `Bearer ${token}` },
  });

  if (response.status === 404) return false;
  if (!response.ok) return false;
  return true;
}

function getConfig() {
  return new Promise((resolve) => {
    chrome.storage.local.get("config", (result) => {
      resolve(result.config || { serverUrl: "", token: "" });
    });
  });
}

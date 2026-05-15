// Tiny wrapper around chrome.storage.local that returns Promises and
// degrades to a single global ("config") record holding {serverUrl, token}.

const STORAGE_KEY = "config";

export async function getConfig() {
  return new Promise((resolve) => {
    chrome.storage.local.get(STORAGE_KEY, (result) => {
      resolve(result[STORAGE_KEY] || { serverUrl: "", token: "" });
    });
  });
}

export async function setConfig(partial) {
  const current = await getConfig();
  const next = { ...current, ...partial };
  return new Promise((resolve) => {
    chrome.storage.local.set({ [STORAGE_KEY]: next }, () => resolve(next));
  });
}

export async function clearConfig() {
  return new Promise((resolve) => {
    chrome.storage.local.remove(STORAGE_KEY, () => resolve());
  });
}

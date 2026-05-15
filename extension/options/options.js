import { getConfig, setConfig, clearConfig } from "../lib/storage.js";
import { importBookmarks } from "../lib/api.js";

const els = {
  serverUrl: document.getElementById("server-url"),
  token: document.getElementById("token"),
  configForm: document.getElementById("config-form"),
  configStatus: document.getElementById("config-status"),
  saveConfig: document.getElementById("save-config"),
  clearConfig: document.getElementById("clear-config"),
  importForm: document.getElementById("import-form"),
  importFile: document.getElementById("import-file"),
  importBtn: document.getElementById("import-btn"),
  importStatus: document.getElementById("import-status"),
};

init();

async function init() {
  const config = await getConfig();
  els.serverUrl.value = config.serverUrl || "";
  els.token.value = config.token || "";

  els.configForm.addEventListener("submit", async (e) => {
    e.preventDefault();
    const serverUrl = els.serverUrl.value.trim();
    const token = els.token.value.trim();
    await setConfig({ serverUrl, token });
    setStatus(els.configStatus, "Saved.", "success");
  });

  els.clearConfig.addEventListener("click", async () => {
    await clearConfig();
    els.serverUrl.value = "";
    els.token.value = "";
    setStatus(els.configStatus, "Cleared.", "success");
  });

  els.importForm.addEventListener("submit", async (e) => {
    e.preventDefault();
    const file = els.importFile.files[0];
    if (!file) return;

    setStatus(els.importStatus, "Importing…");
    els.importBtn.disabled = true;

    try {
      const result = await importBookmarks(file);
      setStatus(
        els.importStatus,
        `Imported ${result.url_count} bookmarks across ${result.tag_count} tags.`,
        "success",
      );
    } catch (err) {
      setStatus(
        els.importStatus,
        `Error: ${err.body?.msg || err.message}`,
        "error",
      );
    } finally {
      els.importBtn.disabled = false;
    }
  });
}

function setStatus(node, text, kind) {
  node.textContent = text;
  node.className = `status muted${kind ? " " + kind : ""}`;
}

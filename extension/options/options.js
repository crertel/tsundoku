import { getConfig, setConfig, clearConfig } from "../lib/storage.js";
import { importBookmarks, getImportStatus } from "../lib/api.js";

const POLL_INTERVAL_MS = 1000;
const TERMINAL_STATES = new Set(["completed", "discarded", "cancelled"]);

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

    setStatus(els.importStatus, "Uploading…");
    els.importBtn.disabled = true;

    try {
      const { job_id, url_count, tag_count } = await importBookmarks(file);
      setStatus(
        els.importStatus,
        `Queued ${url_count} bookmarks (${tag_count} tags). Importing…`,
      );
      await pollUntilDone(job_id, url_count);
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

async function pollUntilDone(jobId, totalHint) {
  while (true) {
    await sleep(POLL_INTERVAL_MS);

    let status;
    try {
      status = await getImportStatus(jobId);
    } catch (err) {
      setStatus(
        els.importStatus,
        `Lost track of import job ${jobId}: ${err.message}`,
        "error",
      );
      return;
    }

    const processed = status.processed ?? 0;
    const total = status.total || totalHint || 0;

    if (status.state === "completed") {
      setStatus(
        els.importStatus,
        `Imported ${status.sites_inserted ?? processed} new bookmarks ` +
          `and ${status.tags_inserted ?? 0} new tags.`,
        "success",
      );
      return;
    }

    if (TERMINAL_STATES.has(status.state)) {
      setStatus(
        els.importStatus,
        `Import ${status.state} (${processed}/${total} processed).`,
        "error",
      );
      return;
    }

    setStatus(els.importStatus, `Importing… ${processed} / ${total}`);
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function setStatus(node, text, kind) {
  node.textContent = text;
  node.className = `status muted${kind ? " " + kind : ""}`;
}

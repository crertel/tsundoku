import { getConfig } from "../lib/storage.js";
import {
  listTags,
  findBookmark,
  randomBookmark,
  createBookmark,
  updateBookmark,
} from "../lib/api.js";

const els = {
  heading: document.getElementById("heading"),
  subheading: document.getElementById("subheading"),
  needsConfig: document.getElementById("needs-config"),
  openOptions: document.getElementById("open-options"),
  saveForm: document.getElementById("save-form"),
  titleInput: document.getElementById("title-input"),
  urlInput: document.getElementById("url-input"),
  notesInput: document.getElementById("notes-input"),
  activeTags: document.getElementById("active-tags"),
  newTagInput: document.getElementById("new-tag-input"),
  addTagBtn: document.getElementById("add-tag-btn"),
  tagSuggestions: document.getElementById("tag-suggestions"),
  saveBtn: document.getElementById("save-btn"),
  cancelBtn: document.getElementById("cancel-btn"),
  yoloBtn: document.getElementById("yolo-btn"),
  status: document.getElementById("status"),
};

const state = {
  existingId: null,
  activeTags: [],
};

init();

async function init() {
  const config = await getConfig();
  if (!config.serverUrl || !config.token) {
    els.needsConfig.hidden = false;
    els.openOptions.addEventListener("click", (e) => {
      e.preventDefault();
      chrome.runtime.openOptionsPage();
    });
    return;
  }

  els.saveForm.hidden = false;

  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab) {
    setStatus("Couldn't read the active tab.", "error");
    return;
  }

  els.titleInput.value = tab.title || "";
  els.urlInput.value = tab.url || "";

  // Tag autocomplete + existing-bookmark detection run in parallel.
  const [allTags, existing] = await Promise.all([
    listTags().catch(() => []),
    findBookmark(tab.url).catch(() => null),
  ]);

  for (const tag of allTags) {
    const opt = document.createElement("option");
    opt.value = tag.name;
    els.tagSuggestions.appendChild(opt);
  }

  if (existing) {
    state.existingId = existing.id;
    els.heading.textContent = "Update bookmark";
    els.subheading.textContent = "This page is already saved.";
    els.saveBtn.textContent = "Update";
    els.titleInput.value = existing.display_name || tab.title || "";
    els.notesInput.value = existing.notes || "";
    state.activeTags = [...(existing.tags || [])];
    renderActiveTags();
  }

  wireUp();
}

function wireUp() {
  els.addTagBtn.addEventListener("click", addCurrentTag);
  els.newTagInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") {
      e.preventDefault();
      addCurrentTag();
    }
  });
  els.cancelBtn.addEventListener("click", () => window.close());
  els.yoloBtn.addEventListener("click", onYolo);
  els.saveForm.addEventListener("submit", onSubmit);
  els.activeTags.addEventListener("click", (e) => {
    if (e.target.matches("button[data-tag]")) {
      state.activeTags = state.activeTags.filter(
        (t) => t !== e.target.dataset.tag,
      );
      renderActiveTags();
    }
  });
}

function addCurrentTag() {
  const value = els.newTagInput.value.trim();
  if (!value) return;
  if (!state.activeTags.includes(value)) state.activeTags.push(value);
  els.newTagInput.value = "";
  renderActiveTags();
}

function renderActiveTags() {
  els.activeTags.innerHTML = "";
  for (const tag of state.activeTags) {
    const li = document.createElement("li");
    const removeBtn = document.createElement("button");
    removeBtn.type = "button";
    removeBtn.dataset.tag = tag;
    removeBtn.textContent = "×";
    removeBtn.title = `Remove ${tag}`;
    li.appendChild(removeBtn);
    li.appendChild(document.createTextNode(tag));
    els.activeTags.appendChild(li);
  }
}

async function onSubmit(e) {
  e.preventDefault();
  setStatus("Saving…");
  els.saveBtn.disabled = true;

  const payload = {
    title: els.titleInput.value.trim(),
    url: els.urlInput.value.trim(),
    tags: state.activeTags,
    notes: els.notesInput.value,
  };

  try {
    if (state.existingId) {
      await updateBookmark(state.existingId, payload);
      setStatus("Updated.", "success");
    } else {
      await createBookmark(payload);
      setStatus("Saved.", "success");
    }
    setTimeout(() => window.close(), 500);
  } catch (err) {
    setStatus(`Error: ${err.body?.msg || err.message}`, "error");
    els.saveBtn.disabled = false;
  }
}

async function onYolo() {
  setStatus("Picking…");
  els.yoloBtn.disabled = true;
  try {
    const bookmark = await randomBookmark();
    if (!bookmark) {
      setStatus("No bookmarks yet.", "error");
      els.yoloBtn.disabled = false;
      return;
    }
    await chrome.tabs.create({ url: bookmark.url });
    window.close();
  } catch (err) {
    setStatus(`Error: ${err.body?.msg || err.message}`, "error");
    els.yoloBtn.disabled = false;
  }
}

function setStatus(text, kind) {
  els.status.textContent = text;
  els.status.className = `status muted${kind ? " " + kind : ""}`;
}

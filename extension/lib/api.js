// Thin fetch wrapper that adds the Bearer token and returns parsed JSON.
// Throws on non-2xx so callers can use try/catch.

import { getConfig } from "./storage.js";

class ApiError extends Error {
  constructor(status, body) {
    super(`API ${status}`);
    this.status = status;
    this.body = body;
  }
}

async function request(path, opts = {}) {
  const { serverUrl, token } = await getConfig();
  if (!serverUrl) throw new ApiError(0, "Server URL not configured");
  if (!token) throw new ApiError(0, "Token not configured");

  const url = serverUrl.replace(/\/$/, "") + path;
  const headers = { Authorization: `Bearer ${token}`, ...(opts.headers || {}) };

  const response = await fetch(url, { ...opts, headers });
  const text = await response.text();
  let body;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = text;
  }

  if (!response.ok) throw new ApiError(response.status, body);
  return body;
}

export async function listTags() {
  const { tags } = await request("/api/tags");
  return tags;
}

export async function randomBookmark() {
  try {
    const { bookmark } = await request("/api/random_bookmark");
    return bookmark;
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) return null;
    throw err;
  }
}

export async function findBookmark(url) {
  try {
    const { bookmark } = await request(
      `/api/find_bookmark?url=${encodeURIComponent(url)}`,
    );
    return bookmark;
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) return null;
    throw err;
  }
}

export async function createBookmark({ title, url, tags, notes }) {
  return request("/api/create_bookmark", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ title, url, tags, notes }),
  });
}

export async function updateBookmark(id, { title, url, tags, notes }) {
  return request(`/api/update_bookmark/${id}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ title, url, tags, notes }),
  });
}

export async function importBookmarks(file) {
  const formData = new FormData();
  formData.append("file", file);
  return request("/api/import_bookmarks", { method: "POST", body: formData });
}

export { ApiError };

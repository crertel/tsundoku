# Future work

Running list of ideas. Loose categories, rough fun-to-effort estimates.
None of this is committed to a roadmap; the file is a parking lot.

## Quality-of-life polish (small)

- **Notes / description field on each site.** Free-form text. Reason
  *why* you saved it.
- **Auto-fetched metadata at save time.** Favicon, OpenGraph
  description, page title (when the user-provided one is missing).
  Cheap with `Floki` + an HTTP fetch.
- **"Already saved" badge on the toolbar icon** of the extension when
  you visit a page you've bookmarked. `/api/find_bookmark` already
  supports it; just needs a content/script or active-tab listener.
- **Keyboard shortcuts site-wide.** `j`/`k` to walk results, `/` to
  focus search, `e` to edit, `x` to delete with confirmation, etc.
- **Saved searches.** Name a query like "elixir reading" and pin it
  to the nav. URL plus an alias.
- **Inline pill editing** — click a tag pill in the filter bar to
  edit its value in place instead of remove-and-retype.
- **Bulk actions** — select multiple sites in the results, then
  tag/untag/delete/export the selection.

## Search & content (medium)

- **Snapshot / archive of the page at save time.** Either rendered
  HTML or a Readability extract. Survives link rot. Cheap with Floki
  + HTTP; nicer with a headless browser (Playwright / Chromedp).
- **Full-text search across snapshots**, not just titles. Once you
  have content stored, `to_tsvector` actually earns its keep — this
  is the case where FTS beats trigram (stemming + word-set across
  whole-page text). Trigram on titles remains.
- **Link-rot checker.** Periodically `HEAD` every URL; flag 4xx/5xx
  with timestamps. Optional auto-link-to-Wayback fallback.
- **Smart tag suggestions** based on page content. Start with simple
  keyword extraction against the user's existing tag vocabulary. AI
  version (embed-then-cluster) is a bigger step.

## Sharing / surfacing (medium)

- **Per-tag or per-domain RSS/Atom feed.** Subscribe to your own
  "reading" tag externally.
- **Public read-only collections.** Curated lists with a
  shareable URL, opt-in per-list (default private).
- **Random / serendipity view.** "Show me three things I saved and
  haven't revisited in a year." Encourages re-reading.
- **Per-tag dashboards** — graph saves over time, top co-occurring
  tags, etc.

## Extension polish (small)

- **Hotkey to save** (`Ctrl+Shift+D` or similar) with a one-click
  default-tag flow.
- **Inline tag editor** via content script — adds tags without
  opening a popup.
- **Mobile Firefox support.** Extension code is probably close to
  working as-is; needs testing + manifest tweaks.
- **AMO unlisted signing** so Firefox can install the `.xpi` from
  the site without a developer-mode browser.

## Bigger swings

- **Reading-status workflow** (unread → read → archived) with
  per-status views. Turns the server into a Pocket replacement.
- **Mobile share target** (Android share intent → save to your
  server). Needs a small native shim or PWA with a share target.
- **Multi-user sharing primitives.** Invites, follow, collections.
  Significant architectural delta — requires permissions model,
  not just per-user scoping.

## Ops / durability

- **Backup / restore.** JSON dump endpoint + import command. Useful
  for migrations and the paranoid.
- **Health / status page** with DB latency, queue depths if any.
- **URL search-and-replace** for the case where a site moves
  domains and you want to bulk-rewrite saved URLs.

## Open questions

- Should snapshots be opt-in per save, or always-on? (Storage costs
  vs. completeness.)
- If link-rot is detected, do we delete, archive, or just flag? My
  default would be "flag, with a button to either link-to-Wayback
  or delete."
- For full-text snapshot search, the indexing strategy: lazy on
  first search? Background job at save? Inline (slow saves)?

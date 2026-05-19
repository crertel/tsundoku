# Future work

Running list of ideas. Loose categories, rough fun-to-effort estimates.
None of this is committed to a roadmap; the file is a parking lot.

Shipped things are removed from this file once they're done; check
git log for what's actually in.

## At-a-glance

**QoL polish (small)**
1. Site-wide keyboard shortcuts (`j`/`k`/`/`/`e`/`x`)
2. Inline pill editing
3. Saved searches
4. Bulk actions on selected sites

**Crawler / metadata (medium)**
5. Link-rot checker (Oban cron)
6. Page snapshot at save time (+ full-text search across snapshots)
7. Smart tag suggestions from page content

**Surfacing / sharing (medium)**
8. Per-tag / per-domain RSS feed
9. Public read-only shareable collections
10. Per-tag dashboards (saves over time, co-occurring tags)

**Extension polish (small)**
11. Hotkey-to-save with default tags
12. Inline tag editor via content script (skip the popup)
13. Mobile Firefox support
14. AMO unlisted signing for one-click install

**Bigger swings**
15. Reading-status workflow (unread / read / archived)
16. Mobile share target
17. Multi-user sharing primitives (invites, follow, collections)

**Ops / durability**
18. URL search-and-replace (e.g. twitter.com → x.com)
19. Re-fetch failed favicons
20. Periodic Oban job pruning

## Quality-of-life polish (small)

- **Keyboard shortcuts site-wide.** `j` / `k` to walk results, `/`
  to focus search, `e` to edit the focused item, `x` to delete with
  confirmation, `g s` / `g t` for nav. Pure JS, no LV state.
- **Inline pill editing.** Click a filter pill on the sites page to
  edit its value in place rather than X-and-retype. Replace the
  pill markup with a tiny inline form when active.
- **Saved searches.** Name a query like "elixir reading" and pin it
  to the nav. A new schema, a `/searches` LV, a "Save" button on
  the sites page that captures the current `?q=`.
- **Bulk actions.** Select multiple rows on the sites page, then
  tag / untag / delete / export the selection.

## Crawler / metadata extensions (medium)

- **Link-rot checker.** A daily Oban cron job (Oban supports cron
  natively) that re-crawls sites whose `crawled_at` is older than N
  days, refreshing `crawl_status` so `status:http_404` is
  self-maintaining. Cheap given the pipeline we already have.
- **Page snapshot at save time.** Store a Readability-extracted
  page body so titles / search survive link rot. This is the case
  where `to_tsvector` actually earns its keep over title-trigram —
  full-text against snapshot bodies. Two roads: HTML extract via
  Floki + Readability port (cheap, lossy) or headless browser
  (Playwright/Chromedp; richer, heavier).
- **Smart tag suggestions.** Page content → suggest tags from the
  user's existing tag vocabulary. Start with bag-of-words keyword
  match; the embedding version is a bigger step.

## Surfacing / sharing (medium)

- **Per-tag or per-domain RSS/Atom feed.** Subscribe to your own
  "reading" tag externally.
- **Public read-only collections.** Curated lists with a
  shareable URL, opt-in per-list (default private).
- **Per-tag dashboards** — graph saves over time, top co-occurring
  tags, etc.

## Extension polish (small)

- **Hotkey to save** (`Ctrl+Shift+D` or similar) with a one-click
  default-tag flow that skips the popup.
- **Inline tag editor** via content script — adds tags without
  opening a popup.
- **Mobile Firefox support.** Extension code is probably close to
  working as-is; needs testing + manifest tweaks.
- **AMO unlisted signing** so Firefox can install the `.xpi` from
  the site without a developer-mode browser. Mozilla signs unlisted
  XPIs for free; you upload, they auto-review, you swap the file
  on the server. One-time setup, ~5 minutes of clicking.

## Bigger swings

- **Reading-status workflow** (unread → read → archived) with
  per-status views. Turns the server into a Pocket replacement.
- **Mobile share target** (Android share intent → save to your
  server). Needs a small native shim or PWA with a share target.
- **Multi-user sharing primitives.** Invites, follow, collections.
  Significant architectural delta — requires a permissions model,
  not just per-user scoping.

## Ops / durability

- **URL search-and-replace** for the case where a site moves
  domains and you want to bulk-rewrite saved URLs (e.g.
  twitter.com → x.com).
- **Re-fetch failed favicons.** Right now a failed favicon fetch
  records a row with `data: nil` and we never try again. A
  scheduled job to re-attempt those (maybe with exponential
  backoff) would let transient outages self-heal.
- **Periodic Oban job pruning.** Old completed/discarded rows pile
  up in `oban_jobs`; Oban has a `Pruner` plugin for this.

## Open questions

- For snapshots, opt-in per save or always-on? Storage cost vs.
  completeness.
- For link-rot detection, do we delete, archive, or just flag?
  Default would be flag + offer "link to Wayback" / "delete"
  buttons on the show page.
- For full-text snapshot search, indexing strategy: lazy on first
  search, background job at save, or inline (slow saves)?

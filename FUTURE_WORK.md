# Future work

Running list of ideas. Loose categories, rough fun-to-effort estimates.
None of this is committed to a roadmap; the file is a parking lot.

Shipped things are removed from this file once they're done; check
git log for what's actually in.

## At-a-glance

**QoL polish (small)**
1. Bulk actions on selected sites

**Crawler / metadata (medium)**
2. Link-rot checker (Oban cron) — at most daily
3. Page snapshot at save time (+ full-text search across snapshots) — held
4. Smart tag suggestions from page content — held

**Surfacing / sharing (medium)**
5. Public read-only shareable collections — held

**Extension polish**
6. Mobile Firefox support
7. AMO unlisted signing for one-click install — eventually

**Bigger swings**
8. Reading-status workflow (unread / read / archived) — tempting
9. Multi-user sharing primitives (invites, follow, collections) — tempting

## Quality-of-life polish (small)

- **Bulk actions.** Select multiple rows on the sites page, then
  tag / untag / delete / export the selection.

## Crawler / metadata extensions (medium)

- **Link-rot checker.** A daily-ish Oban cron job (Oban supports
  cron natively) that re-crawls sites whose `crawled_at` is older
  than N days, refreshing `crawl_status` so `status:http_404` is
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

- **Public read-only collections.** Curated lists with a
  shareable URL, opt-in per-list (default private).

## Extension polish (small)

- **Mobile Firefox support.** Extension code is probably close to
  working as-is; needs testing + manifest tweaks.
- **AMO unlisted signing** so Firefox can install the `.xpi` from
  the site without a developer-mode browser. Mozilla signs unlisted
  XPIs for free; you upload, they auto-review, you swap the file
  on the server. One-time setup, ~5 minutes of clicking.

## Bigger swings

- **Reading-status workflow** (unread → read → archived) with
  per-status views. Turns the server into a Pocket replacement.
- **Multi-user sharing primitives.** Invites, follow, collections.
  Significant architectural delta — requires a permissions model,
  not just per-user scoping.

## Open questions

- For snapshots, opt-in per save or always-on? Storage cost vs.
  completeness.
- For link-rot detection, do we delete, archive, or just flag?
  Default would be flag + offer "link to Wayback" / "delete"
  buttons on the show page.
- For full-text snapshot search, indexing strategy: lazy on first
  search, background job at save, or inline (slow saves)?

# Tsundoku

A personal bookmarks server. Phoenix + LiveView + Postgres, with a
browser extension, a JSON backup format, an installable PWA on Android,
and per-search Atom feeds.

It's an opinionated personal tool, not multi-tenant SaaS. Each user
owns their own private bookmarks; sharing primitives are deliberately
out of scope.

## Features

- **Bookmarks** with tags, notes, auto-fetched title / description /
  favicon / OG image, and a per-user URL uniqueness constraint.
- **Search**: trigram fuzzy phrase match on titles, plus `tag:`,
  `domain:`, `url:`, `title:`, `metadata:`, `status:` filters (negate
  with `-`). Live typeahead suggestions and pill UI on `/sites`.
- **Saved searches** named and (optionally) published as revokable
  Atom feeds at `/feeds/<uuid>.atom`.
- **Domain index** and **tag index** with their own search; tag pages
  show co-occurring tags and a saves-over-time sparkline; merge-tag
  and delete-all-tagged operations.
- **Crawler / metadata pipeline** in Oban (per-domain mutex for
  politeness), with manual "Re-fetch" on each site.
- **Random / YOLO** action: opens a random saved bookmark.
- **Browser extension** (Manifest V3, Firefox + Chrome) — save the
  current tab, add tags, with an "already saved" toolbar badge.
- **PWA share target** on Android: install the site, then share URLs
  to it from the system share sheet.
- **Backup / restore** (JSON dump endpoint + `mix bookmarks.export`
  and `mix bookmarks.restore` tasks; idempotent restore).
- **Wayback Machine and archive.ph** links on every bookmark.
- **Health dashboard** at `/admin/health`: DB latency, Oban queue
  states, BEAM memory, online users (Phoenix.Presence).
- **Account ops**: empty account (wipe data, keep login) or deactivate
  (wipe and delete).

## Setup

### With Nix (recommended)

A flake provides Erlang 27, Elixir 1.18, esbuild, Tailwind, Postgres
17, and tooling.

```bash
nix develop          # drops you into a shell with everything pinned
mix setup            # deps + ecto.create + migrate + seed + static
mix phx.server       # http://localhost:4000
```

### Without Nix

You'll need Erlang/OTP 27, Elixir 1.18, Postgres 17, esbuild, and
Tailwind CSS available on PATH.

```bash
mix setup
mix phx.server
```

Visit <http://localhost:4000>. Register a user; everything else is
gated.

## Browser extension

The extension lives in `extension/` and is bundled by a Mix task:

```bash
mix extension.build
```

That writes `priv/static/extension/bookmark-server.zip` (Chrome) and
`bookmark-server.xpi` (Firefox), both served at `/extension` once
logged in. The page has install + setup instructions and a one-click
token generator.

## PWA share target (Android)

1. Open the site in Chrome or Firefox for Android.
2. Use "Add to home screen" / "Install app".
3. Share any URL → Tsundoku appears in the share sheet.

A shared link is POSTed to `/share`, saved, and you land on the edit
page so you can add tags.

PWA install requires HTTPS in production.

## Atom feeds

On `/sites`, run a query, then click **Save** to capture it as a named
saved search. On `/searches`, publish the search as a feed — you get a
URL like `/feeds/<uuid>.atom` that you can hand to any RSS reader. The
token *is* the auth; rotate or revoke it from `/searches` when you
want to cut subscribers off.

The feed is rendered fresh per request and served with
`Cache-Control: max-age=600` so polite readers cache for 10 minutes.

## Backup / restore

- Web: `/backup` for download + upload, linked from `/users/settings`.
- CLI: `mix bookmarks.export <email> [path]` and `mix bookmarks.restore <email> <path>`.

Restore is idempotent: existing sites (matched by URL) are kept; their
tag sets get unioned with the dump.

## Layout

- `lib/bookmark_server/` — contexts (`Bookmarks`, `Accounts`,
  `Metadata`), schemas, Oban workers.
- `lib/bookmark_server_web/` — Phoenix endpoint, router, controllers,
  LiveViews, layouts.
- `extension/` — MV3 browser extension source.
- `priv/repo/migrations/` — schema migrations.
- `assets/` — Tailwind + JS source; static files in `assets/static/`
  are copied into `priv/static/` by `mix assets.static`.

## Tests

```bash
mix test
```

Tests use a real Postgres database (no mocks).

## License

Personal project, no license declared. Ask if you want to use it.

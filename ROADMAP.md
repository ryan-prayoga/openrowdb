# ROADMAP

OpenrowDB is built in the open. This roadmap is the live plan — updated as we ship.

## Phase 0 — Foundation (Day 0–1) ✅ in progress

- [x] Repo init, license, README, contributing
- [x] AGENTS.md / CLAUDE.md
- [ ] Xcode SwiftUI skeleton (`apps/mac/`)
- [ ] CI: macOS build workflow
- [ ] Issue + PR templates
- [ ] First commit + push to GitHub
- [ ] Announce on X

## Phase 1 — Connect (Day 2–4)

- [x] Connections sidebar UI (Liquid Glass pass deferred to Phase 4)
- [x] New-connection sheet (host, port, user, password, db)
- [x] Postgres connection via PostgresNIO (`PostgresDriver`)
- [x] MySQL connection via MySQLNIO (`MySQLDriver`)
- [x] Secure credential storage (Keychain) — `SecretStore`
- [x] Connection persistence (`ConnectionStore`, JSON)
- [x] Connection status indicator (sidebar dot + workspace badge)
- [x] SSL toggle (require / prefer / disable) — sheet picker + driver mapping

## Phase 2 — Browse (Day 5–7)

- [x] Table list (schema introspection via information_schema)
- [x] Click table → view first 100 rows
- [x] Results grid (SwiftUI Table, dynamic columns, NULL rendering)
- [x] Pagination (prev / next, "X–Y of total")
- [ ] Column header sort
- [ ] Row counts shown in the table list (count exists, only in pager so far)
- [ ] Multi-schema tree (currently a flat table list)

## Phase 3 — Query (Day 8–10)

- [ ] SQL editor (start with `TextEditor`, upgrade to syntax-aware later)
- [ ] Run query (Cmd+Return)
- [ ] Multi-statement support
- [ ] Query history (local SQLite)
- [ ] Result tabs (multiple queries in tabs)
- [ ] Export results: CSV, JSON

## Phase 4 — Polish (Day 11–13)

- [ ] App icon (custom, native macOS style)
- [ ] Onboarding (first-run experience)
- [ ] Dark mode pass
- [ ] Liquid Glass refinement on all surfaces
- [ ] Keyboard shortcuts documented
- [ ] Empty states for every screen

## Phase 5 — Ship v0.1.0 (Day 14)

- [ ] Sign with Apple Developer cert (or unsigned + quarantine docs)
- [ ] Notarize (if signed)
- [ ] DMG packaging via `create-dmg`
- [ ] GitHub Release with DMG + changelog
- [ ] README badges live
- [ ] Launch tweet + Show HN

## Post v1 — backlog

- [ ] SSH tunneling
- [ ] SQLite driver
- [ ] MongoDB driver
- [ ] Redis driver
- [ ] Schema diff tool
- [ ] ER diagram generator (auto from foreign keys)
- [ ] Saved query snippets
- [ ] Multi-window support
- [ ] Windows port (TBD framework)
- [ ] Linux port (TBD framework)

## Non-goals (v1)

- Cloud sync of connections — local only, period
- AI query generation — out of scope (use Cursor / Claude separately)
- Mobile clients — desktop is hard enough
- ORM / model generation — clients are clients, leave codegen elsewhere

# Changelog

All notable changes to OpenrowDB are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.3] — 2026-06-17

### Fixed

- **Workspace tab autosave crash** — stop cancelling debounced `Task.sleep` in `schedulePersist` (macOS 26 `swift_task_dealloc` abort when typing in SQL editor)

## [0.1.2] — 2026-06-17

### Fixed

- **Postgres connect crash** — replace `PostgresClient` connection pool with a single `PostgresConnection` (no `ConnectionPool.runTimer`, no more abort on connect/test/disconnect)

## [0.1.1] — 2026-06-17

### Fixed

- **Crash on Postgres connect** — `ConnectionPool.runTimer` abort during pool shutdown; disable keep-alive timers and drain the pool cleanly on disconnect
- **`install.sh` piped install** — progress lines no longer corrupt the downloaded artifact path (`info()` → stderr)

## [0.1.0] — 2026-06-17

First public preview. Native macOS database client for PostgreSQL and MySQL.

### Added

- **Connections** — save/edit/delete connections, Keychain passwords, SSL modes, test connection, SSH tunneling
- **Browse** — sidebar schema tree, table search, row counts, paginated grid, column sort, row inspector
- **Query** — SQL editor with syntax highlight, line numbers, autocomplete, multi-statement runs, history, snippets, formatter, EXPLAIN viewer
- **Row editing** — inline insert/edit/delete/duplicate (PK-gated), column filter, copy as INSERT/UPDATE
- **DDL** — table structure editor, create/edit/drop table, export table SQL
- **Transfer** — export/import whole database as `.sql`
- **Power features** — foreign-key navigation, read-only connection mode, workspace tab persistence across restart
- **Polish** — Liquid Glass UI, keyboard shortcuts help (⌘/), onboarding, dark mode, custom app icon

### Requirements

- macOS 26 (Tahoe) or later
- PostgreSQL or MySQL/MariaDB server

### Install

Download `OpenrowDB-0.1.0.dmg` from [GitHub Releases](https://github.com/ryan-prayoga/openrowdb/releases). Drag to Applications.

If the build is unsigned (ad-hoc CI artifact):

```bash
xattr -d com.apple.quarantine /Applications/OpenrowDB.app
```

### Known limitations

- Postgres `rowsAffected` not surfaced (PostgresNIO API gap)
- App Sandbox disabled — required for arbitrary host:port DB connections
- Windows/Linux shells are scaffold-only

[0.1.0]: https://github.com/ryan-prayoga/openrowdb/releases/tag/v0.1.0
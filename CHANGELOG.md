# Changelog

All notable changes to OpenrowDB are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.7] — 2026-06-17

### Fixed

- **Sidebar tree cross-wire** — when two connections share the same name (e.g. two "chinook" connections to different databases), expanding/collapsing one would toggle the other instead. Root cause: `@State` per-view `Bool` leaked between sibling `ForEach` elements during SwiftUI `List` + `.sidebar` style cell recycling. Fix: lifted expand/collapse state to a centralized `Set<UUID>` in `ConnectionsSidebar`, passed down as `@Binding<Bool>` to each `ConnectionNode`.

## [0.1.6] — 2026-06-17

### Fixed

- **`Task.sleep` crash (definitive)** — replaced all `Task.sleep` debounce calls with `DispatchQueue.main.asyncAfter` in workspace tab persistence (`WorkspaceTab.swift`), search (`TableDataView.scheduleSearch`), and column filter (`TableDataView.scheduleColumnFilter`). The v0.1.3/v0.1.4 generation-counter approach was insufficient — `swift_task_dealloc` aborts on macOS 26 / Swift 6 even without explicit cancellation when the concurrency runtime cleans up sleeping tasks on the cooperative thread pool.

### Security

- **TLS certificate verification** — `SSL=require` now uses system trust roots for full certificate verification (PostgresDriver and MySQLDriver). `SSL=prefer` keeps opportunistic TLS without cert check for local/dev databases.

### Fixed (continued)

- **Force-try crash paths** — replaced 4× `try!` in `OpenrowDBApp.makeManager/History/SessionStore/Snippets` fallback paths with nested `do-catch` + `fatalError` with descriptive messages.
- **Info.plist version** — `CFBundleShortVersionString` updated from stale `0.1.0` to `0.1.6`, `CFBundleVersion` from `1` to `7`.

### Changed (web landing site)

- Added `target="_blank" rel="noopener noreferrer"` to all 12+ external links (new `Ext` component + auto-detect in `Btn`).
- Added `og:image`, `twitter:image`, and `canonical` meta tags to `index.html`.
- Removed unused `gsap` dependency from `package.json`.
- Fixed `useEffect` dependency array in `Aurora.tsx`.
- Removed dead exports (`ShinyText`, `GradientText`) from `text.tsx`.

### Added (CI/CD)

- New `rust.yml` GitHub Actions workflow — `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test` on every push/PR touching Rust code.
- `site.yml` — added SSH key cleanup step (`if: always()`), changed `StrictHostKeyChecking` from `no` to `accept-new`.

### Changed (config)

- `.gitignore` — `Package.resolved` now committed for reproducible CI builds.
- Windows `.csproj` — pinned NuGet versions from wildcard (`1.7.*`) to exact.

## [0.1.5] — 2026-06-17

### Fixed

- **Table browse hang** — Postgres and MySQL drivers now serialize all queries through a per-connection actor. Opening a table while the sidebar loads row counts, or paging quickly, was firing overlapping queries on one wire connection and hanging indefinitely instead of crashing.
- **Table reset stuck** — switching tables no longer leaves `isResetting` latched if SwiftUI cancels the in-flight load task. Pagination, sort, and search stay responsive after a table switch.

## [0.1.4] — 2026-06-17

### Fixed

- **Table data view crash (attempt 1)** — search and column-filter debouncing in `TableDataView` switched to a generation-counter approach to avoid cancelling in-flight `Task.sleep` calls. This was an incomplete fix — see v0.1.6 for the definitive solution.

## [0.1.3] — 2026-06-17

### Fixed

- **Workspace tab autosave crash (attempt 1)** — debounced tab persistence in `schedulePersist` switched to a generation-counter approach to avoid cancelling in-flight `Task.sleep` calls. This was an incomplete fix — see v0.1.6 for the definitive solution.

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

[0.1.6]: https://github.com/ryan-prayoga/openrowdb/releases/tag/v0.1.6
[0.1.5]: https://github.com/ryan-prayoga/openrowdb/releases/tag/v0.1.5
[0.1.4]: https://github.com/ryan-prayoga/openrowdb/releases/tag/v0.1.4
[0.1.3]: https://github.com/ryan-prayoga/openrowdb/releases/tag/v0.1.3
[0.1.2]: https://github.com/ryan-prayoga/openrowdb/releases/tag/v0.1.2
[0.1.1]: https://github.com/ryan-prayoga/openrowdb/releases/tag/v0.1.1
[0.1.0]: https://github.com/ryan-prayoga/openrowdb/releases/tag/v0.1.0
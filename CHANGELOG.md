# Changelog

All notable changes to OpenrowDB are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.2.1] — 2026-07-07

### Fixed

- **Postgres rows affected** — mutation queries (`UPDATE`, `DELETE`, `INSERT`) now surface affected-row counts in the results pane and query history via PostgresNIO `PostgresQueryMetadata`.

### Changed

- **ROADMAP** — Tier A (v0.2.0 sprints A–H) and Tier B pre-v1 backlog documented.

## [0.2.0] — 2026-07-07

### Added

- **Preferences (⌘,)** — default table page size, editor font size, history display limit, confirm-before-replace on history load.
- **Onboarding sample connections** — Local Postgres / Local MySQL presets open a pre-filled connection sheet.
- **Connection form validation** — per-field errors on Save / Test Connection; **URL import** for `postgres://` / `mysql://` strings.
- **Global search (⌘K)** — command palette across connections, tables (connected), open tabs, and query history.
- **Query tab auto-title** — suggests a tab name from the SQL `FROM` clause; **history pin** with pinned-first sort; **history search** in the inspector.
- **Edit menu** — Undo / Redo / Find routed to the active SQL editor; **Help** links to GitHub and Report Issue.
- **Multi-select rows** — bulk delete and copy-as-TSV in the table viewer; **paste rows (⇧⌘V)** from clipboard TSV/CSV with preview.
- **Column width persistence** — per-table grid column sizes saved across sessions.
- **Typed inline editors** — boolean, date, datetime, and JSON controls inferred from SQL column types.
- **Table filter operators** — Contains, Equals, Not equals, `>`, `<`, Starts with, Ends with (persisted per table tab).
- **Workspace breadcrumb** — `db › schema › table` navigation subtitle.
- **Driver badge icons** on connection sidebar rows; **expandable schema folders** (auto-expand while filtering).
- **Duplicate connection**; sidebar filter now matches connection names.
- **DDL preview** before structure saves; **index editor** (create/drop secondary indexes); **foreign key editor** (add/drop constraints).
- **Rename table sheet**; **tab drag-reorder** and **persisted tab rename**; **Close Others / Close All** on the tab strip.

### Changed

- **DesignSystem** — `PlaceholderView`, `GlassIconButton`, `GlassMenuRow`, and spacing tokens shared across surfaces.
- **Transfer menu** — native `Menu` replaced with a glass popover; import SQL confirms statement count.
- **Shortcuts help (⌘/)** — documents ⌘K, ⇧⌘V, multi-select, and More-menu actions.

### Fixed

- **Export error feedback** — CSV/JSON export failures show an alert instead of failing silently.
- **DDL/mutation errors** — specific messages replace generic “Operation failed” alerts.
- **Query results sort** — sortable headers disabled for ad-hoc query results (no no-op affordance).

## [0.1.9] — 2026-06-26

### Added

- **Schema browser sidebar** — connections expand to databases → schemas → tables → columns, with inline row counts (`~` for estimates) and column types. Any database on the server is browsable without switching the connection.
- **Sidebar SQL/DDL actions** — right-click menus: table New / Rename / Drop / Truncate / Edit Structure / Export-as-SQL; database New / Drop / Export-as-SQL; Copy CREATE statement; Copy Name / Copy Qualified Name on tables and columns; Refresh.
- **Partial run** — ⌘↩ runs the selection or the statement under the caret; ⇧⌘↩ runs all. Run menu exposes Run Selection / Run Current Statement / Run All Statements.
- **Editor status bar** — live `Ln · Col`, selection length, and char/line counts.
- **Getting-started hints** — a fresh query tab shows key shortcuts in the results pane instead of an empty void.
- **Jump to error** — a failed result moves the caret to the offending token.
- **Line-number gutter** — a hairline divider separates the line numbers from the code.

### Removed

- **Row-limit toolbar control** — the auto-`LIMIT` picker is removed; queries always run exactly as written.

### Fixed

- **Gutter seam** — the line-number ruler no longer bleeds a full-height vertical line behind the toolbar and results. The hosted `NSScrollView` ruler composited outside the editor frame; `compositingGroup()` + `clipped()` contains it.
- **Row inspector rounded corner** — the table viewer's right inspector rendered as an inset rounded-corner glass card (native `.inspector`), notching the content. Replaced with a flush, square trailing pane via `safeAreaInset` (`leadingInset` no longer needed, so the grid inherits the sidebar safe area normally).

## [0.1.8] — 2026-06-19

### Changed

- **Connection header moved to title bar** — connection name and `driver · user@host:port/db` subtitle now live in the macOS window title bar via `.navigationTitle` + `.navigationSubtitle`. The inline header bar (44pt) is removed, giving more vertical space to data. Transfer menu and read-only badge moved to the window toolbar. Disconnect removed from the toolbar — available via right-click on the connection in the sidebar.
- **Action bar redesign** — search collapses to a magnifying-glass icon by default and expands with a spring animation on click (ESC or blur-when-empty collapses it). Column filter becomes a single icon button; clicking opens a popover with column picker + value field. Filter button turns accent-colored when a filter is active.
- **Pagination bar** — uses `ViewThatFits` to switch between full layout (Page N of M · range · picker) and compact layout (N/M · range) when the sidebar is wide.
- **Icon button sizing** — all icon-only buttons in the action bar use `Image(...).frame(16×16)` so `.glass` button style applies uniform padding to all.
- **Sidebar expand state** — `ConnectionNode` now owns its own `@State private var expanded` instead of receiving a `Set<UUID>` binding, removing the last source of cross-wire between identically-named connections.
- **Transfer menu** — dropped `.menuStyle(.borderlessButton)` so it renders as a standard macOS toolbar popup button.

### Fixed

- **Pagination bar hidden under glass sidebar** — added `leadingInset` offset so nav buttons and page-info text are not obscured by the translucent NavigationSplitView overlay.

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

- App Sandbox disabled — required for arbitrary host:port DB connections
- Windows/Linux shells are scaffold-only

[0.2.1]: https://github.com/ryan-prayoga/openrowdb/releases/tag/v0.2.1
[0.2.0]: https://github.com/ryan-prayoga/openrowdb/releases/tag/v0.2.0
[0.1.9]: https://github.com/ryan-prayoga/openrowdb/releases/tag/v0.1.9
[0.1.8]: https://github.com/ryan-prayoga/openrowdb/releases/tag/v0.1.8
[0.1.7]: https://github.com/ryan-prayoga/openrowdb/releases/tag/v0.1.7
[0.1.6]: https://github.com/ryan-prayoga/openrowdb/releases/tag/v0.1.6
[0.1.5]: https://github.com/ryan-prayoga/openrowdb/releases/tag/v0.1.5
[0.1.4]: https://github.com/ryan-prayoga/openrowdb/releases/tag/v0.1.4
[0.1.3]: https://github.com/ryan-prayoga/openrowdb/releases/tag/v0.1.3
[0.1.2]: https://github.com/ryan-prayoga/openrowdb/releases/tag/v0.1.2
[0.1.1]: https://github.com/ryan-prayoga/openrowdb/releases/tag/v0.1.1
[0.1.0]: https://github.com/ryan-prayoga/openrowdb/releases/tag/v0.1.0
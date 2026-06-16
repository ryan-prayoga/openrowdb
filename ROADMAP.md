# ROADMAP

OpenrowDB is built in the open. This roadmap is the live plan — updated as we ship.

## Phase 0 — Foundation (Day 0–1) ✅

- [x] Repo init, license, README, contributing
- [x] AGENTS.md / CLAUDE.md
- [x] SwiftUI app via SwiftPM (`apps/mac/`)
- [x] CI: macOS build workflow (`.github/workflows/macos-build.yml`)
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
- [x] Edit / delete connection (delete confirmed; secret cleanup best-effort)
- [x] Test Connection button + password show/hide
- [x] Double-click connection to connect; friendly connection errors

## Phase 2 — Browse (Day 5–7)

- [x] Table list (introspection: tables + views, grouped by schema)
- [x] Search filter + hybrid row-count badges (exact small / ~estimate large)
- [x] Click table → first 100 rows; reusable ResultsGrid component
- [x] Results grid (SwiftUI Table, dynamic columns, NULL rendering, cell copy)
- [x] Column header sort (server-side ORDER BY)
- [x] Row inspector (per-row column/value + SQL types, copyable)
- [x] Pagination (prev / next / jump, page-size picker, big-data safe)
- [x] Refresh (⌘R: tables + counts + current page)
- [x] Connection-loss detection (demotes status, offers reconnect)

## Phase 3 — Query (Day 8–10)

- [x] SQL editor (native `NSTextView` via `CodeEditor` wrapper — system colors, undo, find bar, ⌘Return / ⌘. shortcuts, status line)
- [x] Run query (⌘Return runs, ⌘. cancels in-flight)
- [x] Multi-statement support (string/identifier/comment-aware `;` splitter, per-statement outcomes)
- [x] Query history (local SQLite via GRDB, `QueryHistoryStore`, sidebar inspector with reload-into-editor)
- [x] Result tabs (per-connection Workspace tabs: Browse + N Query scratchpads; ⌘T new, ⌘W close)
- [x] Export results: CSV (RFC 4180) + JSON; copy + save-to-disk via `NSSavePanel`

## Phase 3.5 — Smoke-test fixes & quality of life

- [x] Surface real Postgres/MySQL server errors (SQLSTATE/errno + message + hint) instead of NIO's redacted "Generic description"
- [x] SQL autocomplete (Tab key): dialect-aware keywords (~150 each) + live schema (tables, columns after `table.`) — pure provider with 12 unit tests
- [x] Open table as workspace tab (double-click in Browse, or right-click → Open in New Tab; dedups + per-tab page/sort state)

## Phase 4 — Polish (Day 11–13)

- [x] App icon (custom, native macOS style) — indigo→blue squircle; `scripts/make-icons.sh` generates all sizes into `Assets.xcassets`
- [x] Onboarding (first-run experience) — `OnboardingView` shown on first launch via UserDefaults gate, opens New Connection sheet on dismiss
- [x] Dark mode pass — all colors use system semantics (`system*`, `.primary`, `.secondary`, `.tertiary`, `textBackgroundColor`, `labelColor`); adapts automatically
- [x] Liquid Glass refinement on all surfaces — tab strip chips use `.glassEffect()` inside `GlassEffectContainer`; all buttons already on `.glass` / `.glassProminent`
- [x] Keyboard shortcuts documented — `ShortcutsHelpView` via Help → Keyboard Shortcuts… (⌘/)
- [x] Empty states for every screen — `PlaceholderView` + `EmptyStateView`

## Phase 4.5 — Row editing, DDL & transfer (post Phase 4) ✅

- [x] Inline row insert / edit / delete / duplicate (`TableDataView`, PK-gated)
- [x] Table structure editor tab — create + edit (add/remove/rename columns)
- [x] Database transfer — export schema+data, import `.sql`
- [x] Sidebar DDL — new table, edit structure, export table SQL, drop table

## Phase 4.6 — Pre-release maturity ✅

- [x] ⌘R refresh — sidebar tree, row counts, active table page, schema catalog
- [x] Shortcuts help aligned with inline row editing (removed dead sheet references)
- [x] Structure editor loads real nullability + defaults via `columnDefinitions`
- [x] Saved query snippets — `QuerySnippetStore` + snippets panel per connection
- [x] SQL formatter — `SQLFormatter` + ⌘⇧F in query editor
- [x] Copy row as INSERT / UPDATE — table viewer context menu
- [x] Column filter — per-column substring filter in table viewer
- [x] Line numbers — gutter ruler in SQL editor
- [x] Rows affected — MySQL driver reports via `onMetadata` (Postgres pending NIO API)
- [x] SSH tunneling — `SSHTunnelManager` via `/usr/bin/ssh`, connection sheet section
- [x] Explain plan viewer — `ExplainPlanView` + toolbar button in query editor
- [x] Foreign key navigation — `ForeignKeyRef` introspection + Follow FK in row inspector
- [x] Read-only connection mode — `SQLWriteDetector` guards + UI badges / disabled DDL
- [x] Tab persistence across restart — `WorkspaceSessionStore` (`workspace.json`)
- [ ] …see pre-release plan for full Tier A/B backlog

## Phase 5 — Ship v0.1.0 (Day 14)

- [ ] Sign with Apple Developer cert (or unsigned + quarantine docs)
  - `OpenrowDB.entitlements` → `OpenrowDB/Resources/OpenrowDB.entitlements` (network + Keychain)
  - `Info.plist` → `OpenrowDB/Resources/Info.plist` (bundle ID `com.openrowdb.mac`, LSCategory developer-tools)
  - Open `Package.swift` in Xcode, set Team + Bundle ID in target signing settings
- [ ] Notarize (if signed) — `xcrun notarytool submit … --wait && xcrun stapler staple`
- [x] DMG packaging script — `scripts/make-dmg.sh` (requires `brew install create-dmg` + signed .app)
- [ ] GitHub Release with DMG + changelog
- [ ] README badges live
- [ ] Launch tweet + Show HN

## Post v1 — backlog
- [ ] SQLite driver
- [ ] MongoDB driver
- [ ] Redis driver
- [ ] Schema diff tool
- [ ] ER diagram generator (auto from foreign keys)

- [ ] Multi-window support
- [ ] Windows port (full — see **Cross-platform architecture** below)
- [ ] Linux port (full — see **Cross-platform architecture** below)

## Cross-platform architecture (post v1)

> **Decision locked 2026-06-16.** Scaffold only for now — macOS v1 ships first.
> Other agents: read this section + `apps/windows/README.md` + `apps/linux/README.md`
> + `crates/openrowdb-core/README.md` before touching cross-platform code.

### Principle: native UI per platform, shared headless core

| Platform | UI shell | Language | Core library | Path |
|----------|----------|----------|--------------|------|
| **macOS** (v1) | SwiftUI + Liquid Glass | Swift 6 | `OpenrowDBCore` (Swift) | `apps/mac/` |
| **Linux** | GTK 4 + libadwaita | Rust | `openrowdb-core` (Rust) | `apps/linux/` |
| **Windows** | WinUI 3 (Fluent Design) | C# / .NET 9 | `openrowdb-core` (Rust, via FFI) | `apps/windows/` |

**Shared Rust core:** `crates/openrowdb-core` — port target for everything in
`apps/mac/Sources/OpenrowDBCore/` (drivers, SQL dialect, splitter, export, etc.).
Linux links the crate directly; Windows consumes it through **cbindgen / uniffi FFI**
once the API stabilizes. macOS keeps Swift core until v1 ships; Rust becomes the
cross-platform source of truth afterward.

### Rejected stacks (do not propose these)

- **Electron / Tauri / web views** — violates native-first rule (AGENTS.md)
- **Avalonia** — cross-platform .NET UI; less native than WinUI on Windows, less
  native than GTK on GNOME
- **Qt 6** — heavier binaries, licensing nuance; GTK + WinUI are more native per OS

### Init status ✅ (scaffold only)

- [x] Rust workspace root `Cargo.toml` + `crates/openrowdb-core` (stub modules, unit tests)
- [x] Linux placeholder app — GTK 4 + libadwaita window (`cargo run -p openrowdb-linux`)
- [x] Windows placeholder app — WinUI 3 unpackaged shell (`apps/windows/OpenrowDB.sln`)
- [ ] Port Swift `OpenrowDBCore` → Rust (drivers, dialect, history, export, dump…)
- [ ] Linux: connections sidebar + workspace UI
- [ ] Windows: FFI bridge + WinUI feature modules
- [ ] CI: `ubuntu-latest` (Rust/GTK build) + `windows-latest` (.NET/WinUI build)

### Developing from macOS (solo dev reality)

| Target | Build on Mac? | Run UI on Mac? | Recommended test path |
|--------|---------------|----------------|------------------------|
| `openrowdb-core` | ✅ | ✅ (headless) | `cargo test -p openrowdb-core` |
| Linux shell | ✅ (`brew install gtk4 libadwaita`) | ✅ (rough; not real GNOME) | CI on Ubuntu for real Linux |
| Windows shell | ❌ | ❌ | GitHub Actions `windows-latest` or Windows VM |

WinUI 3 requires Windows SDK — no official macOS build path. Day-to-day cross-platform
work on a Mac = Rust core tests + optional Linux GTK smoke; platform UI verified in CI/VM.

## Non-goals (v1)

- Cloud sync of connections — local only, period
- AI query generation — out of scope (use Cursor / Claude separately)
- Mobile clients — desktop is hard enough
- ORM / model generation — clients are clients, leave codegen elsewhere

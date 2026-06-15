# AGENTS.md

Guidance for AI coding agents (Claude Code, Codex, Cursor, Grok, Hermes) working on OpenrowDB.

## Project at a glance

- **Product**: native macOS database GUI client (Postgres + MySQL first)
- **Stack**: Swift 6, SwiftUI, Liquid Glass (macOS 26 Tahoe)
- **License**: MIT
- **Maintainer**: solo dev (Ryan Prayoga, @txtdrprogrammer)
- **Layout**: monorepo. Current code lives in `apps/mac/`. Other platforms are placeholders.

## Golden rules

1. **No AI slop.** Verify APIs exist before calling them. Do not invent SwiftUI modifiers or PostgresNIO methods. When unsure, read the source / docs first.
2. **Native first.** No Electron, no Tauri, no JS bridges. Pure Swift + SwiftUI.
3. **No CDN deps.** No remote fonts, no remote images at runtime. Bundle everything.
4. **Liquid Glass is the design language.** Use `.glassEffect()` and `GlassEffectContainer` (macOS 26 APIs). Avoid manual blur hacks.
5. **Async/await everywhere.** No completion handlers, no Combine for new code.
6. **Strict concurrency.** Swift 6 mode, `Sendable` everywhere, no `@unchecked`.
7. **No force-unwraps** in non-test code unless commented why.

## Folder conventions

```
apps/mac/
├── OpenrowDB/                    # Main app target
│   ├── App/                      # App entry, scenes
│   ├── Features/                 # Feature modules (connections/, query-editor/, results-grid/)
│   ├── Core/                     # DB drivers, models, storage
│   ├── DesignSystem/             # Tokens, components, Liquid Glass wrappers
│   └── Resources/                # Assets, localizations
├── OpenrowDBTests/               # Unit tests
└── OpenrowDBUITests/             # UI tests
```

## Coding style

- 2-space indent for Swift.
- File header: just the filename comment, no copyright block (LICENSE covers it).
- Group related types in one file when small; split when > 200 lines.
- Prefer `struct` over `class` unless reference semantics required.
- `MARK: -` to section files: `// MARK: - State`, `// MARK: - Body`, `// MARK: - Helpers`.

## Commits

Conventional Commits. Always.

```
feat(connections): add SSH tunnel support
fix(query-editor): handle paste of multi-statement SQL
docs: update README install steps
refactor(core): extract ConnectionPool from ConnectionManager
chore: bump Swift toolchain to 6.1
test(query-editor): cover empty result set rendering
```

Scope is optional but encouraged for non-trivial changes.

## Pull requests

- Title = Conventional Commit subject
- Body: what / why / how to test
- Link issue: `Closes #N`
- Self-review the diff before requesting review
- Run `cmd+U` (tests) and `swiftformat .` before pushing

## Testing

- Unit tests for `Core/` (DB drivers, parsers, models)
- UI tests for critical flows (connect → query → render)
- Snapshot tests for `DesignSystem/` components (use `swift-snapshot-testing`)

## Dependencies

Keep deps minimal. Currently approved:
- `PostgresNIO` (Postgres driver)
- `MySQLNIO` (MySQL driver)
- `swift-collections` (OrderedDictionary, Deque)
- `swift-snapshot-testing` (test only)

Adding a new dep requires a PR with justification.

## What NOT to do

- Don't add analytics, telemetry, or "phone home" code without an issue + discussion first
- Don't pull in Electron, React Native, Flutter, or any cross-platform shim
- Don't bundle a JS engine
- Don't introduce a build tool other than Xcode + SwiftPM
- Don't commit `.xcuserdata/`, `DerivedData/`, or signing artifacts
- Don't hardcode connection credentials in tests; use `OPENROWDB_TEST_*` env vars

## When stuck

1. Read `ROADMAP.md` to understand current phase
2. Check open issues for prior discussion
3. If genuinely unsure, open a draft issue rather than guessing
4. Ask the maintainer in PR comments — clarity over speed

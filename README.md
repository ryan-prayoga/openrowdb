<div align="center">

# OpenrowDB

**A modern, native database client — open source from day one.**

Built with SwiftUI + Liquid Glass for macOS. Postgres & MySQL first.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-blue)](https://www.apple.com/macos/)
[![macOS Build](https://github.com/ryan-prayoga/openrowdb/actions/workflows/macos-build.yml/badge.svg)](https://github.com/ryan-prayoga/openrowdb/actions/workflows/macos-build.yml)
[![Release](https://img.shields.io/github/v/release/ryan-prayoga/openrowdb?label=release)](https://github.com/ryan-prayoga/openrowdb/releases)
[![Built with AI](https://img.shields.io/badge/built%20with-Claude%20%2B%20Codex-purple)]()

</div>

---

## Why OpenrowDB?

Database GUI clients today are stuck between two extremes: powerful but ugly (DBeaver, HeidiSQL), or beautiful but closed-source (TablePlus, Navicat).

**OpenrowDB is the third option** — beautiful, native, and fully open source.

- 🍎 **Native macOS feel** — built with SwiftUI + Liquid Glass (macOS 26 Tahoe)
- ⚡ **Fast** — no Electron, no JVM, no compromise
- 🔓 **MIT licensed** — fork it, ship it, sell it, we don't care
- 🤖 **AI-assisted development** — built in the open with Claude Code, Codex, and Grok

## Status

🎉 **v0.1.0 preview** — macOS client ready for daily use with Postgres + MySQL. See [CHANGELOG](./CHANGELOG.md).

| Platform | Status | Tech |
|----------|--------|------|
| macOS 26+ | ✅ v0.1.0 preview | SwiftUI + Liquid Glass |
| Windows | 🧱 Scaffolded (post v1) | WinUI 3 + .NET 9 |
| Linux | 🧱 Scaffolded (post v1) | GTK 4 + libadwaita (Rust) |

Shared Rust core for Windows/Linux: `crates/openrowdb-core`.

## Supported Databases (v1)

- ✅ PostgreSQL (via PostgresNIO)
- ✅ MySQL / MariaDB (via MySQLNIO)
- 📋 SQLite, MongoDB, Redis — post v1

## Install

**One-liner** (unsigned build, no Apple Developer ID):

```bash
curl -fsSL https://openrowdb.ryanprayoga.dev/install.sh | bash
```

Or **[download from Releases](https://github.com/ryan-prayoga/openrowdb/releases)** / [openrowdb.ryanprayoga.dev](https://openrowdb.ryanprayoga.dev).

```bash
# Manual quarantine fix if needed:
xattr -cr /Applications/OpenrowDB.app
open /Applications/OpenrowDB.app
```

```bash
# Homebrew cask — coming soon
# brew install --cask openrowdb
```

> Signed + notarized builds ship once an Apple Developer cert is configured.
> Maintainer release command: `cd apps/mac && ./scripts/release.sh 0.1.0`

## Build from source

Requires macOS 26+ and Xcode 26+.

```bash
git clone https://github.com/ryan-prayoga/openrowdb.git
cd openrowdb/apps/mac

# Build + test the core + app via SwiftPM
swift build
swift test

# Launch the app (builds, wraps in a .app bundle, ad-hoc signs, opens)
scripts/run.sh

# Package a release DMG (unsigned ad-hoc by default)
./scripts/release.sh 0.1.0
```

> `scripts/make-app.sh` produces a proper `.app` bundle (Info.plist, icon,
> entitlements-ready signing). Set `SIGN_IDENTITY` for Developer ID signing and
> `NOTARIZE=1` after configuring `notarize.sh` credentials.

## Project layout

```
openrowdb/
├── apps/
│   ├── mac/        # SwiftUI app (current focus)
│   ├── windows/    # placeholder — coming after v1
│   └── linux/      # placeholder — coming after v1
├── shared/         # design tokens, icons, copy
├── docs/           # user + developer docs
├── .github/        # workflows, issue templates
├── AGENTS.md       # AI agent conventions
├── CLAUDE.md       # → AGENTS.md
├── ROADMAP.md      # 14-day v1 plan
└── CONTRIBUTING.md
```

## Contributing

Contributions are very welcome! See [CONTRIBUTING.md](./CONTRIBUTING.md) for the full guide.

Quick start:
1. Pick an issue labeled `good first issue` or `help wanted`
2. Fork, branch, code, commit (Conventional Commits)
3. Open a PR — be kind, be clear

## Built with AI

OpenrowDB is developed in the open as an experiment in AI-driven solo development. Daily progress is logged on [X / Twitter @txtdrprogrammer](https://x.com/txtdrprogrammer).

Stack: Claude Code · Codex CLI · Grok · Hermes Agent

## License

[MIT](./LICENSE) © 2026 Ryan Prayoga

---

<div align="center">

Made with 🇮🇩 in Indonesia.

</div>

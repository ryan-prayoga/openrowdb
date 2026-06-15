<div align="center">

# OpenrowDB

**A modern, native database client — open source from day one.**

Built with SwiftUI + Liquid Glass for macOS. Postgres & MySQL first.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-blue)](https://www.apple.com/macos/)
[![Status](https://img.shields.io/badge/status-alpha-orange)]()
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

🚧 **Alpha — active development.** First release targeted within 2 weeks of repo creation.

| Platform | Status | Tech |
|----------|--------|------|
| macOS 26+ | 🏗️ In development | SwiftUI + Liquid Glass |
| Windows | 📋 Planned (post v1) | TBD |
| Linux | 📋 Planned (post v1) | TBD |

## Supported Databases (v1)

- ✅ PostgreSQL (via PostgresNIO)
- ✅ MySQL / MariaDB (via MySQLNIO)
- 📋 SQLite, MongoDB, Redis — post v1

## Install

```bash
# Homebrew (preferred — once published)
brew install --cask openrowdb

# Manual download
# Grab the latest DMG from Releases, then:
xattr -d com.apple.quarantine /Applications/OpenrowDB.app
open /Applications/OpenrowDB.app
```

> The quarantine flag removal is needed because v1 ships unsigned. Once we have an Apple Developer cert, this step goes away.

## Build from source

Requires macOS 26+ and Xcode 26+.

```bash
git clone https://github.com/ryan-prayoga/openrowdb.git
cd openrowdb/apps/mac

# Build + test the core + app via SwiftPM
swift build
swift test
swift run OpenrowDB   # launch the app
```

> A packaged `.xcodeproj` (Info.plist, entitlements, codesign) arrives in
> Phase 5. Until then the app builds and runs straight from SwiftPM.

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

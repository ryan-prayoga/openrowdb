# Contributing to OpenrowDB

Thanks for considering a contribution! OpenrowDB is solo-maintained right now, so PRs and ideas mean a lot.

## Quick rules

- **Be kind.** Disagree on code, never on people.
- **Small PRs win.** One concern per PR. Easier to review, easier to merge.
- **Conventional Commits.** `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`, `test:`.
- **No AI slop.** AI-assisted code is welcome (we use it ourselves), but please review and test before submitting. A PR full of hallucinated APIs wastes everyone's time.

## Getting started

### Prerequisites

- macOS 26 Tahoe or later (Apple Silicon recommended)
- Xcode 26+ with Swift 6 toolchain
- Git + GitHub account

### Setup

```bash
git clone https://github.com/ryan-prayoga/openrowdb.git
cd openrowdb/apps/mac
open OpenrowDB.xcodeproj
```

Hit Cmd+R. App should launch.

### Local testing

Spin up a Postgres + MySQL locally with Docker:

```bash
docker run --name pg -e POSTGRES_PASSWORD=test -p 5432:5432 -d postgres:16
docker run --name my -e MYSQL_ROOT_PASSWORD=test -p 3306:3306 -d mysql:8
```

Use these to test connection flows.

## Workflow

1. **Find an issue** labeled `good first issue` or `help wanted`. Comment to claim it.
2. **Fork** the repo, branch from `main`:
   ```bash
   git checkout -b feat/your-feature
   ```
3. **Code.** Keep it focused. Follow conventions in [AGENTS.md](./AGENTS.md).
4. **Commit** with Conventional Commits:
   ```bash
   git commit -m "feat(connections): add SSH tunnel support"
   ```
5. **Test** locally. `cmd+U` in Xcode runs the suite.
6. **Push & PR.** Reference the issue: `Closes #42`.

## Code style

- **Swift 6** concurrency-strict mode.
- **2-space indent** for Swift files.
- **SwiftFormat** runs on save (config in repo root once we add it).
- **No force-unwraps** (`!`) in non-test code unless explicitly justified.
- **Comments explain *why*, not *what***.

## Design contributions

UI/UX feedback is gold. Open an issue with:
- Screenshot or mockup
- Specific problem you're solving
- Reference apps you'd compare against

We're aiming for TablePlus-level polish, native macOS feel, and Liquid Glass throughout.

## Reporting bugs

Use the bug report template. Include:
- macOS version
- Xcode version (if building from source)
- Database type & version
- Steps to reproduce
- Expected vs actual behavior

## Asking questions

GitHub Discussions for open-ended chat. Issues for bugs/features only.

## License

By contributing, you agree your code is released under the [MIT License](./LICENSE).

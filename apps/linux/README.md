# apps/linux

Native Linux shell for OpenrowDB.

## Stack (chosen)

| Layer | Tech | Why |
|-------|------|-----|
| **UI** | **GTK 4 + libadwaita** | Native GNOME look, GPU-accelerated, lightweight (~few MB vs Electron hundreds of MB) |
| **Language** | **Rust** | Same language as shared core; memory-safe, fast |
| **Core** | `crates/openrowdb-core` | Shared with Windows via Rust (Linux links directly) |

### Why not Qt?

Qt 6 is excellent on KDE and cross-desktop, but GTK 4 + libadwaita is the most
native path on GNOME (Ubuntu, Fedora Workstation, Pop!_OS default). We optimize
for GNOME first; KDE users still get a solid GTK app.

### Why not Avalonia / Electron?

Cross-platform .NET or Chromium stacks trade native feel and binary size for
code sharing. This repo's rule is **native first** — same reason macOS uses
SwiftUI, not a web view.

## Prerequisites (Linux)

```bash
# Debian / Ubuntu
sudo apt install libgtk-4-dev libadwaita-1-dev

# Fedora
sudo dnf install gtk4-devel libadwaita-devel

# Arch
sudo pacman -S gtk4 libadwaita
```

Rust 1.85+ via [rustup](https://rustup.rs).

## Build & run

From repo root:

```bash
cargo run -p openrowdb-linux
```

Release binary:

```bash
cargo build -p openrowdb-linux --release
./target/release/openrowdb
```

## Layout

```
apps/linux/
├── Cargo.toml          # GTK shell binary
├── src/main.rs         # Application entry + placeholder window
└── README.md
```

Feature modules (connections sidebar, workspace tabs, query editor) will mirror
`apps/mac/OpenrowDB/Features/` as native GTK widgets.

## Status

🚧 **Initialized** — empty shell window, core crate linked. Drivers + UI next.
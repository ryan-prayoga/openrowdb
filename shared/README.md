# shared/

Cross-platform assets that all apps consume.

Platform stacks (see `apps/windows/README.md`, `apps/linux/README.md`):

| Platform | UI shell | Shared core |
|----------|----------|-------------|
| macOS | SwiftUI + Liquid Glass | `apps/mac/Sources/OpenrowDBCore` (Swift) |
| Linux | GTK 4 + libadwaita (Rust) | `crates/openrowdb-core` (Rust) |
| Windows | WinUI 3 (C#) | `crates/openrowdb-core` (Rust, via FFI) |

Assets:
- Design tokens (colors, spacing, radii)
- Icon source files
- Copy / strings (when we internationalize)
- Brand kit

Stuff in here should be platform-agnostic (no Swift, no C#, no Rust). Each platform app converts these into their native format at build time.

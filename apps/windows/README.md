# apps/windows

Native Windows shell for OpenrowDB.

## Stack (chosen)

| Layer | Tech | Why |
|-------|------|-----|
| **UI** | **WinUI 3** | Official Windows 11 UI (Fluent Design), GPU-accelerated, no Chromium |
| **Language** | **C# / .NET 9** | First-class WinUI support, fast dev velocity on Windows |
| **Core** | `crates/openrowdb-core` (Rust) | Shared logic; consumed via FFI once API stabilizes |

### Why not Avalonia?

Avalonia shares UI code with Linux but never feels as native as WinUI on Windows
(title bar, Mica/Acrylic, snap layouts, shell integration). We pick **per-platform
native UI** over cross-platform UI reuse.

### Why not Qt?

Qt is solid but heavier, licensing is nuanced for commercial forks, and WinUI 3
is the Microsoft-endorsed native path for new Windows desktop apps.

### Why not Tauri / Electron?

Violates the repo rule: **no Electron, no JS engine, no web view shell**.

## Prerequisites (Windows)

- Windows 10 1809+ or Windows 11
- [Visual Studio 2022 17.10+](https://visualstudio.microsoft.com/) with:
  - **.NET desktop development** workload
  - **Windows application development** workload (WinUI 3 / Windows App SDK)
- [.NET 9 SDK](https://dotnet.microsoft.com/download)

## Build & run

```powershell
cd apps\windows
dotnet restore
dotnet build OpenrowDB.sln
dotnet run --project OpenrowDB\OpenrowDB.csproj
```

Or open `OpenrowDB.sln` in Visual Studio and press F5.

## Layout

```
apps/windows/
├── OpenrowDB.sln
├── global.json              # .NET SDK pin
└── OpenrowDB/
    ├── OpenrowDB.csproj     # WinUI 3 unpackaged app
    ├── App.xaml
    ├── MainWindow.xaml      # Placeholder shell
    └── app.manifest
```

Feature modules will mirror `apps/mac/OpenrowDB/Features/` as WinUI pages / controls.

## Core integration plan

1. Port Swift `OpenrowDBCore` logic into `crates/openrowdb-core`
2. Expose a C API (`cbindgen`) or `uniffi` bindings
3. P/Invoke from C# into `openrowdb_core.dll` shipped beside the exe

macOS keeps Swift core for v1; Rust core becomes the cross-platform source of truth.

## Status

🚧 **Initialized** — empty WinUI window. Build on Windows only (no cross-compile from macOS).
# apps/mac

The macOS app. SwiftUI + Liquid Glass, Postgres & MySQL via NIO drivers.

## Layout

```
apps/mac/
├── Package.swift                       # SwiftPM target for the Core library
├── OpenrowDB/                          # Xcode app target source
│   ├── App/                            # App entry, scene, root views
│   ├── Features/                       # Feature modules
│   │   ├── Connections/                # Sidebar + new-connection sheet
│   │   └── Workspace/                  # Schema tree + query editor + results
│   ├── Core/                           # (placeholder — heavy lifting lives in Sources/OpenrowDBCore)
│   ├── DesignSystem/                   # Liquid Glass wrappers, tokens
│   └── Resources/                      # Assets, localizations
├── Sources/OpenrowDBCore/              # SwiftPM library: drivers, models, persistence
├── Tests/OpenrowDBCoreTests/           # Unit tests
└── OpenrowDB.xcodeproj                 # Generated locally; not committed beyond skeleton
```

## Why split SwiftPM `Sources/OpenrowDBCore` from the Xcode app?

- Core logic can be tested headlessly via `swift test` (no Xcode required → CI is faster + simpler)
- The Xcode target just depends on the local SwiftPM package
- When we add Windows / Linux later, they can also depend on the same Swift core (where applicable)

## Running

Until the Xcode project is generated:

```bash
cd apps/mac
swift build           # builds the Core library
swift test            # runs Core tests
```

Once `OpenrowDB.xcodeproj` exists, just open it and Cmd+R.

## Generating the Xcode project

The `.xcodeproj` is not committed — it's noisy and prone to merge conflicts. Generate it locally:

```bash
# Once we adopt xcodegen (planned):
brew install xcodegen
cd apps/mac
xcodegen generate
open OpenrowDB.xcodeproj
```

Until then, create the project manually via Xcode (File → New → Project → macOS → App, name `OpenrowDB`), then drag the `OpenrowDB/` folder into it and add the local SwiftPM package as a dependency.

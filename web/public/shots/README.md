# App screenshots

Drop real OpenrowDB captures here and they appear automatically in the
Showcase section (each frame falls back to a placeholder until its file exists):

| File            | What to capture                                              |
| --------------- | ------------------------------------------------------------ |
| `browse.png`    | Browse tab — results grid with rows (e.g. a `cinema_tix` table) + sidebar |
| `query.png`     | SQL editor — a multi-statement query with results below      |
| `structure.png` | Table structure editor — columns / types                     |

Tips:
- Capture the window only: `⌘⇧4` then `Space`, click the window (drops a clean shadow).
- Roughly **16:10** looks best (frames are `aspect-[16/10]`, `object-cover` top-aligned).
- Keep them reasonable (< ~600 KB each); they're served as-is.

After adding files: commit + push to `main` → CI rebuilds and deploys automatically.

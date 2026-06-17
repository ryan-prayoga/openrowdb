# openrowdb-core (Rust)

Portable core shared by **Linux** (GTK) and **Windows** (WinUI) shells.

macOS keeps `apps/mac/Sources/OpenrowDBCore` (Swift) for v1. This crate is the
long-term home for logic that must behave identically across desktop platforms:

- Connection models + persistence
- Postgres / MySQL drivers
- `SQLDialect`, statement splitting, tokenizer, autocomplete provider
- Query history, result export, SQL dump / mutations

## Port order (mirror mac roadmap)

1. `connection` + `dialect` + `statement_splitter`
2. Drivers (`postgres`, `mysql`)
3. `result_exporter`, `query_history`
4. `sql_dump`, `sql_mutations`

Swift implementations in `apps/mac/Sources/OpenrowDBCore/` are the reference.

## Build

```bash
cargo test -p openrowdb-core
```

Windows will consume this via **uniffi** or **cbindgen** FFI once the API
surface stabilizes — not wired yet.
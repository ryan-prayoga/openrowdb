/*
 * Feature content — sourced verbatim from ROADMAP.md / README.md.
 * Do not list anything not actually shipped (see ROADMAP "✅" items).
 */

export interface Pillar {
  key: string;
  label: string;
  title: string;
  blurb: string;
  accent: string;
  items: string[];
}

export const pillars: Pillar[] = [
  {
    key: "connect",
    label: "Connect",
    title: "Secure connections in seconds",
    blurb: "Postgres & MySQL with Keychain-backed secrets and real SSH tunnels.",
    accent: "#6366f1",
    items: [
      "PostgreSQL via PostgresNIO",
      "MySQL / MariaDB via MySQLNIO",
      "Keychain credential storage",
      "SSL modes — require / prefer / disable",
      "SSH tunneling over /usr/bin/ssh",
      "Test connection + friendly errors",
    ],
  },
  {
    key: "browse",
    label: "Browse",
    title: "Read your data, fast",
    blurb: "A native grid that stays smooth on big tables — counts, sort, paginate.",
    accent: "#2f6bff",
    items: [
      "Schema tree — tables + views",
      "Hybrid row counts (exact / estimate)",
      "Sortable grid, NULL-aware, cell copy",
      "Row inspector with SQL types",
      "Pagination + page-size + jump",
      "Foreign-key navigation (Follow FK)",
    ],
  },
  {
    key: "query",
    label: "Query",
    title: "A real SQL workspace",
    blurb: "Native editor with history, autocomplete, EXPLAIN, and exports.",
    accent: "#38e1d6",
    items: [
      "Multi-statement editor (⌘↩ run / ⌘. cancel)",
      "Query history + saved snippets",
      "Dialect-aware autocomplete (Tab)",
      "EXPLAIN plan viewer",
      "SQL formatter (⌘⇧F)",
      "Export results — CSV (RFC 4180) + JSON",
    ],
  },
  {
    key: "power",
    label: "Power",
    title: "Edit with confidence",
    blurb: "Inline editing, DDL, transfer — guarded by read-only mode.",
    accent: "#f5b545",
    items: [
      "Inline row insert / edit / delete / duplicate",
      "Table structure editor (columns, types)",
      "Database transfer — export & import .sql",
      "Copy row as INSERT / UPDATE",
      "Read-only connection mode + guards",
      "Tab persistence across restarts",
    ],
  },
];

export interface Stat {
  to: number;
  prefix?: string;
  suffix?: string;
  label: string;
}

export const stats: Stat[] = [
  { to: 0, label: "lines of Electron" },
  { to: 2, label: "engines (PG + MySQL)" },
  { to: 150, suffix: "+", label: "autocomplete keywords / dialect" },
  { to: 100, suffix: "%", label: "open source · MIT" },
];

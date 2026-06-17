/* Platform + database status — from README.md "Status" / "Supported Databases". */

export interface Platform {
  name: string;
  status: string;
  state: "shipped" | "scaffold";
  tech: string;
}

export const platforms: Platform[] = [
  { name: "macOS 26+", status: "v0.1.0 preview", state: "shipped", tech: "SwiftUI + Liquid Glass" },
  { name: "Windows", status: "Scaffolded · post v1", state: "scaffold", tech: "WinUI 3 + .NET 9" },
  { name: "Linux", status: "Scaffolded · post v1", state: "scaffold", tech: "GTK 4 + libadwaita (Rust)" },
];

export interface DbSupport {
  name: string;
  state: "ready" | "soon";
  note: string;
}

export const databases: DbSupport[] = [
  { name: "PostgreSQL", state: "ready", note: "via PostgresNIO" },
  { name: "MySQL / MariaDB", state: "ready", note: "via MySQLNIO" },
  { name: "SQLite", state: "soon", note: "post v1" },
  { name: "MongoDB", state: "soon", note: "post v1" },
  { name: "Redis", state: "soon", note: "post v1" },
];

export const links = {
  repo: "https://github.com/ryan-prayoga/openrowdb",
  releases: "https://github.com/ryan-prayoga/openrowdb/releases",
  releasesLatest: "https://github.com/ryan-prayoga/openrowdb/releases/latest",
  x: "https://x.com/txtdrprogrammer",
  install: "curl -fsSL https://openrowdb.ryanprayoga.dev/install.sh | bash",
};

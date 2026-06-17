/*
 * AppWindowFrame — a hi-fidelity, CSS/React replica of the OpenrowDB macOS
 * window used as the hero visual. Not a screenshot: traffic lights, a
 * connection sidebar with live status dots, a syntax-coloured SQL editor, a
 * glass tab strip, and a results grid with typed cells. Purely decorative.
 */

const KW = "text-accent";
const FN = "text-cyan";
const NUM = "text-emerald";

function Dot({ color }: { color: string }) {
  return (
    <span
      className="inline-block h-2 w-2 shrink-0 rounded-full"
      style={{ background: color, color, boxShadow: `0 0 8px ${color}` }}
    />
  );
}

const rows = [
  { id: 1, name: "Ryan Prayoga", email: "ryan@openrow.dev", plan: "pro", active: true },
  { id: 2, name: "Adi Nugraha", email: "adi@studio.id", plan: "team", active: true },
  { id: 3, name: "Sari Wijaya", email: "sari@kirana.co", plan: "free", active: false },
  { id: 4, name: "Bima Saputra", email: null, plan: "pro", active: true },
  { id: 5, name: "Niken Larasati", email: "niken@waktu.app", plan: "team", active: true },
];

const planColor: Record<string, string> = {
  pro: "text-accent border-accent/40 bg-accent/10",
  team: "text-cyan border-cyan/40 bg-cyan/10",
  free: "text-muted border-hair bg-glass",
};

export function AppWindowFrame() {
  return (
    <div className="glass overflow-hidden rounded-[var(--radius-glass)] text-[12px] leading-none select-none">
      {/* Title bar */}
      <div className="flex items-center gap-3 border-b border-hair bg-white/[0.03] px-4 py-3">
        <div className="flex gap-2">
          <span className="h-3 w-3 rounded-full bg-[#ff5f57]" />
          <span className="h-3 w-3 rounded-full bg-[#febc2e]" />
          <span className="h-3 w-3 rounded-full bg-[#28c840]" />
        </div>
        <div className="flex-1 text-center font-mono text-[11px] text-faint">
          production-pg · OpenrowDB
        </div>
        <div className="flex items-center gap-1.5 rounded-md border border-hair bg-glass px-2 py-1 font-mono text-[10px] text-emerald">
          <Dot color="#36d399" /> connected
        </div>
      </div>

      <div className="flex h-[330px]">
        {/* Sidebar */}
        <div className="no-scrollbar hidden w-[164px] shrink-0 overflow-y-auto border-r border-hair bg-black/20 p-3 sm:block">
          <div className="mb-2 px-1 font-mono text-[9px] tracking-[0.2em] text-faint uppercase">
            Connections
          </div>
          {[
            ["production-pg", "#36d399"],
            ["staging-mysql", "#36d399"],
            ["analytics-rds", "#f5b545"],
            ["localhost", "#5b6377"],
          ].map(([name, c], i) => (
            <div
              key={name}
              className={`mb-0.5 flex items-center gap-2 rounded-md px-2 py-1.5 ${
                i === 0 ? "bg-accent/15 text-fg" : "text-muted"
              }`}
            >
              <Dot color={c} />
              <span className="truncate font-mono text-[11px]">{name}</span>
            </div>
          ))}

          <div className="mt-4 mb-2 px-1 font-mono text-[9px] tracking-[0.2em] text-faint uppercase">
            public · tables
          </div>
          {[
            ["users", true],
            ["orders", false],
            ["payments", false],
            ["sessions", false],
            ["audit_log", false],
          ].map(([t, active]) => (
            <div
              key={t as string}
              className={`flex items-center gap-2 rounded-md px-2 py-1.5 font-mono text-[11px] ${
                active ? "bg-white/[0.06] text-fg" : "text-faint"
              }`}
            >
              <svg width="11" height="11" viewBox="0 0 16 16" className="shrink-0 opacity-70">
                <rect x="1.5" y="2.5" width="13" height="11" rx="1.5" fill="none" stroke="currentColor" />
                <path d="M1.5 6h13M6 6v7.5" stroke="currentColor" />
              </svg>
              {t}
            </div>
          ))}
        </div>

        {/* Main */}
        <div className="flex min-w-0 flex-1 flex-col">
          {/* Tab strip */}
          <div className="flex items-center gap-1.5 border-b border-hair px-3 py-2">
            <span className="flex items-center gap-1.5 rounded-md border border-hair bg-white/[0.06] px-2.5 py-1.5 font-mono text-[10px] text-fg">
              <Dot color="#5b7cfa" /> users
            </span>
            <span className="rounded-md px-2.5 py-1.5 font-mono text-[10px] text-faint">orders</span>
            <span className="rounded-md border border-hair bg-glass px-2.5 py-1.5 font-mono text-[10px] text-cyan">
              ⌘ SQL
            </span>
          </div>

          {/* Query editor */}
          <div className="border-b border-hair bg-black/25 px-4 py-3 font-mono text-[11px] leading-relaxed">
            <div className="flex gap-3">
              <span className="select-none text-faint">1</span>
              <code className="whitespace-pre-wrap">
                <span className={KW}>SELECT</span> id, name, email, plan{" "}
                <span className={KW}>FROM</span> <span className={FN}>users</span>
                {"\n   "}
                <span className={KW}>WHERE</span> active = <span className={NUM}>true</span>{" "}
                <span className={KW}>ORDER BY</span> created_at <span className={KW}>DESC</span>{" "}
                <span className={KW}>LIMIT</span> <span className={NUM}>100</span>;
                <span className="ml-0.5 inline-block h-3.5 w-[2px] translate-y-0.5 bg-accent [animation:caret_1.1s_step-end_infinite]" />
              </code>
            </div>
          </div>

          {/* Results grid */}
          <div className="no-scrollbar flex-1 overflow-auto">
            <table className="w-full border-collapse text-left font-mono text-[10.5px]">
              <thead>
                <tr className="text-faint">
                  {["id", "name", "email", "plan", "active"].map((h) => (
                    <th
                      key={h}
                      className="sticky top-0 border-b border-hair bg-ink-2/80 px-3 py-2 font-normal backdrop-blur"
                    >
                      {h}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {rows.map((r, i) => (
                  <tr
                    key={r.id}
                    className={`border-b border-hair/60 ${i === 0 ? "bg-accent/[0.07]" : ""}`}
                  >
                    <td className="px-3 py-2 text-emerald">{r.id}</td>
                    <td className="px-3 py-2 text-fg">{r.name}</td>
                    <td className="px-3 py-2">
                      {r.email ? (
                        <span className="text-muted">{r.email}</span>
                      ) : (
                        <span className="rounded bg-glass px-1 text-[9px] text-faint italic">NULL</span>
                      )}
                    </td>
                    <td className="px-3 py-2">
                      <span className={`rounded border px-1.5 py-0.5 text-[9px] ${planColor[r.plan]}`}>
                        {r.plan}
                      </span>
                    </td>
                    <td className="px-3 py-2">
                      <Dot color={r.active ? "#36d399" : "#5b6377"} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Status bar */}
          <div className="flex items-center justify-between border-t border-hair bg-black/20 px-4 py-2 font-mono text-[10px] text-faint">
            <span>100 rows · 12 ms</span>
            <span className="flex items-center gap-1.5">
              <Dot color="#5b7cfa" /> Postgres 16.2
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}

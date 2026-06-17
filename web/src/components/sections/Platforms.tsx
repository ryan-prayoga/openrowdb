import { Reveal, Section, Eyebrow } from "../ui/primitives";
import { databases, platforms } from "../../data/platforms";

export function Platforms() {
  return (
    <Section id="platforms">
      <Reveal>
        <Eyebrow>Engines &amp; platforms</Eyebrow>
      </Reveal>
      <Reveal delay={0.05}>
        <h2 className="max-w-3xl text-[clamp(1.9rem,4vw,3rem)]">
          Postgres &amp; MySQL today. <span className="text-gradient">More on the way.</span>
        </h2>
      </Reveal>

      <div className="mt-12 grid grid-cols-1 gap-10 lg:grid-cols-2">
        {/* Databases */}
        <Reveal>
          <div className="glass h-full rounded-[var(--radius-glass)] p-7">
            <h3 className="mb-5 text-lg text-fg">Supported databases</h3>
            <ul className="space-y-2.5">
              {databases.map((d) => (
                <li
                  key={d.name}
                  className="flex items-center justify-between rounded-xl border border-hair bg-glass px-4 py-3"
                >
                  <span className="flex items-center gap-3">
                    <span
                      className={`h-2 w-2 rounded-full ${d.state === "ready" ? "bg-emerald" : "bg-faint"}`}
                    />
                    <span className="font-medium text-fg">{d.name}</span>
                  </span>
                  <span className="flex items-center gap-3 text-sm">
                    <span className="text-faint">{d.note}</span>
                    <span
                      className={`rounded-full border px-2.5 py-0.5 font-mono text-[10px] uppercase ${
                        d.state === "ready"
                          ? "border-emerald/40 bg-emerald/10 text-emerald"
                          : "border-hair bg-glass text-muted"
                      }`}
                    >
                      {d.state === "ready" ? "Ready" : "Soon"}
                    </span>
                  </span>
                </li>
              ))}
            </ul>
          </div>
        </Reveal>

        {/* Platforms */}
        <Reveal delay={0.08}>
          <div className="glass h-full rounded-[var(--radius-glass)] p-7">
            <h3 className="mb-5 text-lg text-fg">Platforms</h3>
            <ul className="space-y-2.5">
              {platforms.map((p) => (
                <li
                  key={p.name}
                  className="flex items-center justify-between rounded-xl border border-hair bg-glass px-4 py-3"
                >
                  <span>
                    <span className="font-medium text-fg">{p.name}</span>
                    <span className="ml-2 text-xs text-faint">{p.tech}</span>
                  </span>
                  <span
                    className={`rounded-full border px-2.5 py-0.5 font-mono text-[10px] ${
                      p.state === "shipped"
                        ? "border-accent/40 bg-accent/10 text-accent"
                        : "border-hair bg-glass text-muted"
                    }`}
                  >
                    {p.status}
                  </span>
                </li>
              ))}
            </ul>
            <p className="mt-5 text-sm text-faint">
              A shared Rust core (<span className="font-mono text-muted">openrowdb-core</span>) powers
              the Windows &amp; Linux ports after v1.
            </p>
          </div>
        </Reveal>
      </div>
    </Section>
  );
}

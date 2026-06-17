import { SpotlightCard } from "../bits/cards";
import { Reveal, Section, Eyebrow } from "../ui/primitives";
import { pillars } from "../../data/features";

export function Pillars() {
  return (
    <Section id="features">
      <Reveal>
        <Eyebrow>Built for daily use</Eyebrow>
      </Reveal>
      <Reveal delay={0.05}>
        <h2 className="max-w-3xl text-[clamp(1.9rem,4vw,3rem)]">
          Everything you reach for, <span className="text-gradient">natively</span>.
        </h2>
      </Reveal>

      {/* Even 2×2 grid — balanced, no orphan card */}
      <div className="mt-12 grid grid-cols-1 gap-4 md:grid-cols-2">
        {pillars.map((p, i) => (
          <Reveal key={p.key} delay={i * 0.06} className="h-full">
            <SpotlightCard
              spotlightColor={`${p.accent}33`}
              className="glass glass-hover flex h-full flex-col rounded-[var(--radius-glass)] p-7"
            >
              <span
                className="mb-4 inline-flex w-fit items-center gap-2 rounded-full border px-3 py-1 font-mono text-[11px] tracking-wider uppercase"
                style={{ borderColor: `${p.accent}55`, color: p.accent, background: `${p.accent}12` }}
              >
                {p.label}
              </span>
              <h3 className="text-2xl text-fg">{p.title}</h3>
              <p className="mt-2 text-[15px] text-muted">{p.blurb}</p>

              <ul className="mt-6 grid gap-2.5 border-t border-hair pt-6">
                {p.items.map((item) => (
                  <li key={item} className="flex items-start gap-2.5 text-sm text-muted">
                    <svg
                      width="16"
                      height="16"
                      viewBox="0 0 16 16"
                      className="mt-0.5 shrink-0"
                      style={{ color: p.accent }}
                    >
                      <path
                        d="M3.5 8.5l3 3 6-7"
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="1.6"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                      />
                    </svg>
                    <span>{item}</span>
                  </li>
                ))}
              </ul>
            </SpotlightCard>
          </Reveal>
        ))}
      </div>
    </Section>
  );
}

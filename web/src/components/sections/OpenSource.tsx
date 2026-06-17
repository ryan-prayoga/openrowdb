import { Ext, Reveal, Section, Eyebrow } from "../ui/primitives";
import { links } from "../../data/platforms";

const builtWith = ["Claude Code", "Codex CLI", "Grok", "Hermes Agent"];

export function OpenSource() {
  return (
    <Section className="py-16 sm:py-20">
      <div className="grid grid-cols-1 gap-10 lg:grid-cols-[1fr_0.8fr] lg:items-center">
        <div>
          <Reveal>
            <Eyebrow>Open from day one</Eyebrow>
          </Reveal>
          <Reveal delay={0.05}>
            <h2 className="max-w-xl text-[clamp(1.8rem,3.6vw,2.7rem)]">
              MIT licensed. Built in the open, <span className="text-gradient">with AI.</span>
            </h2>
          </Reveal>
          <Reveal delay={0.1}>
            <p className="mt-5 max-w-xl text-base text-muted">
              OpenrowDB is an experiment in AI-driven solo development — shipped publicly,
              one commit at a time. Fork it, ship it, sell it. Daily progress is logged on X.
            </p>
          </Reveal>
          <Reveal delay={0.15}>
            <div className="mt-6 flex flex-wrap gap-3">
              <Ext
                href={links.repo}
                className="inline-flex items-center gap-2 rounded-xl border border-hair bg-glass px-4 py-2.5 text-sm text-fg transition-colors hover:border-accent"
              >
                ★ Star on GitHub
              </Ext>
              <Ext
                href={links.x}
                className="inline-flex items-center gap-2 rounded-xl border border-hair bg-glass px-4 py-2.5 text-sm text-fg transition-colors hover:border-accent"
              >
                Follow @txtdrprogrammer
              </Ext>
            </div>
          </Reveal>
        </div>

        <Reveal delay={0.1}>
          <div className="glass rounded-[var(--radius-glass)] p-7">
            <div className="mb-4 font-mono text-[11px] tracking-[0.2em] text-faint uppercase">
              Built with
            </div>
            <div className="flex flex-wrap gap-2.5">
              {builtWith.map((t) => (
                <span
                  key={t}
                  className="rounded-lg border border-hair bg-glass px-3 py-2 font-mono text-sm text-muted"
                >
                  {t}
                </span>
              ))}
            </div>
            <div className="mt-6 flex items-center gap-3 border-t border-hair pt-5 text-sm text-muted">
              <span className="rounded-md border border-amber/40 bg-amber/10 px-2 py-0.5 font-mono text-[11px] text-amber">
                MIT
              </span>
              fork it · ship it · sell it — we don't care.
            </div>
          </div>
        </Reveal>
      </div>
    </Section>
  );
}

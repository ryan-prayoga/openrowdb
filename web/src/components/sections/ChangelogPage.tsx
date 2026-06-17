import changelogMd from "../../../../CHANGELOG.md?raw";
import Aurora from "../bits/Aurora";
import { parseChangelog } from "../../lib/parseChangelog";
import { Nav } from "./Nav";
import { Footer } from "./Footer";
import { Reveal, Section, Eyebrow, Pill, Btn } from "../ui/primitives";
import { links } from "../../data/platforms";

const releases = parseChangelog(changelogMd);

const tagColor: Record<string, string> = {
  Added: "border-emerald/40 bg-emerald/10 text-emerald",
  Fixed: "border-amber/40 bg-amber/10 text-amber",
  Changed: "border-accent/40 bg-accent/10 text-accent",
  Removed: "border-rose/40 bg-rose/10 text-rose",
  Security: "border-cyan/40 bg-cyan/10 text-cyan",
  Deprecated: "border-hair bg-glass text-muted",
};

export function ChangelogPage() {
  const latest = releases[0]?.version;

  return (
    <div className="grain relative min-h-screen bg-ink">
      <Nav />

      {/* Header */}
      <section className="relative overflow-hidden pt-36 pb-4 sm:pt-44">
        <div className="pointer-events-none absolute inset-0 -top-32 -z-10 h-[60vh] opacity-60">
          <Aurora colorStops={["#6366f1", "#5b7cfa", "#38e1d6"]} amplitude={0.9} blend={0.5} speed={0.4} />
        </div>
        <div className="pointer-events-none absolute inset-x-0 top-[42vh] -z-10 h-64 bg-gradient-to-b from-transparent to-ink" />

        <div className="mx-auto w-full max-w-3xl px-6">
          <Reveal>
            <Eyebrow>Changelog</Eyebrow>
          </Reveal>
          <Reveal delay={0.05}>
            <h1 className="text-[clamp(2.4rem,5vw,3.6rem)]">
              Every release, <span className="text-gradient">in the open.</span>
            </h1>
          </Reveal>
          <Reveal delay={0.1}>
            <p className="mt-5 max-w-xl text-lg text-muted">
              OpenrowDB ships in small, frequent increments. Here's everything that's changed.
            </p>
          </Reveal>
          <Reveal delay={0.15}>
            <div className="mt-6 flex flex-wrap items-center gap-3">
              {latest && (
                <Pill>
                  <span className="h-1.5 w-1.5 rounded-full bg-emerald" /> Latest · v{latest}
                </Pill>
              )}
              <Btn href={links.releases} variant="ghost" className="!px-4 !py-2 text-[13px]">
                GitHub Releases ↗
              </Btn>
            </div>
          </Reveal>
        </div>
      </section>

      {/* Timeline */}
      <Section className="max-w-3xl pt-8">
        <ol className="relative border-l border-hair pl-6 sm:pl-8">
          {releases.map((rel, i) => (
            <li key={rel.version} className="relative mb-10 last:mb-0">
              {/* node */}
              <span
                className="absolute -left-[34px] top-1.5 flex h-3.5 w-3.5 items-center justify-center sm:-left-[42px]"
                aria-hidden
              >
                <span className="h-3.5 w-3.5 rounded-full border-2 border-accent bg-ink" />
                {i === 0 && (
                  <span className="absolute h-3.5 w-3.5 animate-ping rounded-full bg-accent/40" />
                )}
              </span>

              <Reveal delay={Math.min(i, 4) * 0.04}>
                <article className="glass rounded-[var(--radius-glass)] p-6 sm:p-7">
                  <header className="mb-4 flex flex-wrap items-baseline gap-x-3 gap-y-1">
                    <h2 className="font-display text-2xl text-fg">v{rel.version}</h2>
                    <time className="font-mono text-xs text-faint">{rel.date}</time>
                    {i === 0 && (
                      <span className="rounded-full border border-emerald/40 bg-emerald/10 px-2 py-0.5 font-mono text-[10px] text-emerald">
                        latest
                      </span>
                    )}
                  </header>

                  {rel.intro && <p className="mb-4 text-[15px] text-muted">{rel.intro}</p>}

                  <div className="space-y-4">
                    {rel.sections.map((sec) => (
                      <div key={sec.name}>
                        <span
                          className={`mb-2 inline-block rounded-full border px-2.5 py-0.5 font-mono text-[10px] uppercase ${
                            tagColor[sec.name] ?? "border-hair bg-glass text-muted"
                          }`}
                        >
                          {sec.name}
                        </span>
                        <ul className="space-y-1.5">
                          {sec.items.map((it, j) => (
                            <li key={j} className="flex gap-2.5 text-[15px] text-muted">
                              <span className="mt-2 h-1 w-1 shrink-0 rounded-full bg-faint" />
                              <span>
                                {it.lead && <strong className="font-medium text-fg">{it.lead}</strong>}
                                {it.lead && it.text ? " — " : ""}
                                {it.text}
                              </span>
                            </li>
                          ))}
                        </ul>
                      </div>
                    ))}
                  </div>
                </article>
              </Reveal>
            </li>
          ))}
        </ol>
      </Section>

      <Footer />
    </div>
  );
}

import { Reveal, Section, Eyebrow } from "../ui/primitives";
import { ScreenshotFrame } from "../ui/ScreenshotFrame";

const shots = [
  {
    title: "Browse · users",
    caption: "Sortable, NULL-aware results grid with row inspector and FK navigation.",
    accent: "#2f6bff",
  },
  {
    title: "⌘ SQL editor",
    caption: "Multi-statement editor with history, autocomplete, EXPLAIN and exports.",
    accent: "#38e1d6",
  },
  {
    title: "Structure editor",
    caption: "Edit columns and types, transfer databases, copy rows as INSERT / UPDATE.",
    accent: "#6366f1",
  },
];

export function Showcase() {
  return (
    <Section id="showcase">
      <Reveal>
        <Eyebrow>See it in motion</Eyebrow>
      </Reveal>
      <Reveal delay={0.05}>
        <h2 className="max-w-3xl text-[clamp(1.9rem,4vw,3rem)]">
          Liquid Glass, <span className="text-gradient">all the way down</span>.
        </h2>
      </Reveal>

      <div className="mt-12 grid grid-cols-1 gap-5 [perspective:1400px] lg:grid-cols-3">
        {shots.map((s, i) => (
          <Reveal key={s.title} delay={i * 0.08} className="h-full">
            <ScreenshotFrame {...s} />
          </Reveal>
        ))}
      </div>
    </Section>
  );
}

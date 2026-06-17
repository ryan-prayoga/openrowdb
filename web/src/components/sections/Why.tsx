import { CountUp } from "../bits/text";
import { Reveal, Section, Eyebrow } from "../ui/primitives";
import { stats } from "../../data/features";

export function Why() {
  return (
    <Section className="py-16 sm:py-20">
      <Reveal>
        <Eyebrow>The third option</Eyebrow>
      </Reveal>

      <Reveal delay={0.05}>
        <h2 className="max-w-4xl text-[clamp(1.8rem,3.6vw,2.9rem)]">
          Database clients are stuck between{" "}
          <span className="text-muted">powerful but ugly</span> and{" "}
          <span className="text-muted">beautiful but closed.</span>{" "}
          <span className="text-gradient">OpenrowDB is both — and open.</span>
        </h2>
      </Reveal>

      <Reveal delay={0.1}>
        <p className="mt-5 max-w-2xl text-base text-muted">
          DBeaver and HeidiSQL are capable but feel like 2009. TablePlus and Navicat are
          gorgeous but locked down. OpenrowDB is native, fast, and MIT-licensed — fork it,
          ship it, sell it, we don't care.
        </p>
      </Reveal>

      {/* Stat strip */}
      <Reveal delay={0.15}>
        <dl className="mt-12 grid grid-cols-2 gap-px overflow-hidden rounded-2xl border border-hair bg-hair lg:grid-cols-4">
          {stats.map((s) => (
            <div key={s.label} className="bg-ink-2 p-6">
              <dt className="font-display text-4xl font-semibold tracking-tight text-fg">
                <CountUp to={s.to} prefix={s.prefix} suffix={s.suffix} />
              </dt>
              <dd className="mt-1.5 text-sm text-muted">{s.label}</dd>
            </div>
          ))}
        </dl>
      </Reveal>
    </Section>
  );
}

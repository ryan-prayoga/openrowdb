import Aurora from "../bits/Aurora";
import { InstallCommand } from "../ui/InstallCommand";
import { Btn, Reveal, Section, Eyebrow } from "../ui/primitives";
import { links } from "../../data/platforms";

export function Install() {
  return (
    <Section id="install">
      <div className="glass relative overflow-hidden rounded-[28px] px-6 py-14 sm:px-14">
        {/* faint aurora wash inside the card */}
        <div className="pointer-events-none absolute inset-0 -z-10 opacity-40">
          <Aurora colorStops={["#6366f1", "#5b7cfa", "#38e1d6"]} amplitude={0.8} blend={0.5} speed={0.3} />
        </div>

        <Reveal>
          <Eyebrow>Get OpenrowDB</Eyebrow>
        </Reveal>
        <Reveal delay={0.05}>
          <h2 className="max-w-2xl text-[clamp(1.9rem,4vw,3rem)]">
            One command. <span className="text-gradient">No sign-up, no telemetry.</span>
          </h2>
        </Reveal>

        <div className="mt-8 max-w-2xl">
          <Reveal delay={0.1}>
            <InstallCommand />
          </Reveal>

          <Reveal delay={0.15}>
            <div className="mt-4 flex flex-wrap gap-3">
              <Btn href={links.releasesLatest} variant="primary">
                Download from Releases ↓
              </Btn>
              <Btn href={links.repo} variant="ghost">
                Build from source ↗
              </Btn>
            </div>
          </Reveal>

          <Reveal delay={0.2}>
            <div className="mt-8 grid gap-3 sm:grid-cols-2">
              <div className="rounded-xl border border-hair bg-glass p-4">
                <div className="mb-1 text-xs text-faint">If macOS quarantines the unsigned build</div>
                <code className="block font-mono text-[12px] text-muted">
                  xattr -cr /Applications/OpenrowDB.app
                </code>
              </div>
              <div className="rounded-xl border border-hair bg-glass p-4">
                <div className="mb-1 text-xs text-faint">Homebrew cask</div>
                <code className="block font-mono text-[12px] text-faint">
                  # brew install --cask openrowdb · coming soon
                </code>
              </div>
            </div>
          </Reveal>

          <Reveal delay={0.25}>
            <p className="mt-5 text-sm text-faint">
              Requires macOS 26+. Signed &amp; notarized builds ship once an Apple Developer
              cert is configured.
            </p>
          </Reveal>
        </div>
      </div>
    </Section>
  );
}

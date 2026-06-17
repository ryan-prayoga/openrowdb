import { motion } from "motion/react";
import Aurora from "../bits/Aurora";
import { SplitText } from "../bits/text";
import { AppWindowFrame } from "../ui/AppWindowFrame";
import { InstallCommand } from "../ui/InstallCommand";
import { Btn, Pill } from "../ui/primitives";
import { links } from "../../data/platforms";

export function Hero() {
  return (
    <section id="top" className="relative overflow-hidden pt-36 pb-20 sm:pt-44">
      {/* Aurora background */}
      <div className="pointer-events-none absolute inset-0 -top-32 -z-10 h-[80vh] opacity-80">
        <Aurora colorStops={["#6366f1", "#5b7cfa", "#38e1d6"]} amplitude={1.1} blend={0.55} speed={0.45} />
      </div>
      {/* fade aurora into the page */}
      <div className="pointer-events-none absolute inset-x-0 top-[55vh] -z-10 h-64 bg-gradient-to-b from-transparent to-ink" />

      <div className="mx-auto grid w-full max-w-6xl grid-cols-1 items-center gap-14 px-6 lg:grid-cols-[1.05fr_0.95fr]">
        {/* Left — copy */}
        <div>
          <motion.div
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6 }}
            className="mb-6 flex flex-wrap gap-2"
          >
            <Pill>
              <span className="h-1.5 w-1.5 rounded-full bg-emerald" /> macOS 26+
            </Pill>
            <Pill>Postgres &amp; MySQL</Pill>
            <Pill>MIT · Open Source</Pill>
          </motion.div>

          <h1 className="text-[clamp(2.6rem,6vw,4.2rem)] leading-[1.02]">
            <SplitText text="Native database" />
            <br />
            <SplitText text="client. No" delay={0.18} />{" "}
            <span className="text-gradient">
              <SplitText text="Electron." delay={0.34} />
            </span>
          </h1>

          <motion.p
            initial={{ opacity: 0, y: 14 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.7, delay: 0.5 }}
            className="mt-6 max-w-xl text-lg text-muted"
          >
            SwiftUI + Liquid Glass for macOS Tahoe. Connect, browse, query and edit rows
            across Postgres and MySQL — at the speed of native, fully open source.
          </motion.p>

          <motion.div
            initial={{ opacity: 0, y: 14 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.7, delay: 0.62 }}
            className="mt-8 max-w-xl"
          >
            <InstallCommand label="Install in one command — unsigned build, no Apple Developer ID needed" />
            <div className="mt-4 flex flex-wrap gap-3">
              <Btn href={links.releasesLatest} variant="primary">
                Download release ↓
              </Btn>
              <Btn href={links.repo} variant="ghost">
                View source ↗
              </Btn>
            </div>
          </motion.div>
        </div>

        {/* Right — app window */}
        <motion.div
          initial={{ opacity: 0, y: 30, rotateX: 8 }}
          animate={{ opacity: 1, y: 0, rotateX: 0 }}
          transition={{ duration: 1, delay: 0.35, ease: [0.16, 1, 0.3, 1] }}
          style={{ transformPerspective: 1400 }}
          className="relative"
        >
          <div
            className="pointer-events-none absolute -inset-8 -z-10 rounded-full opacity-60 blur-3xl"
            style={{ background: "radial-gradient(circle,rgba(91,124,250,0.35),transparent 65%)" }}
          />
          <AppWindowFrame />
        </motion.div>
      </div>
    </section>
  );
}

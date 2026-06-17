import { motion } from "motion/react";
import type { ReactNode } from "react";

/* ── Logo — the indigo→blue squircle (matches the app icon + favicon) ───── */
export function Logo({ size = 30, withWordmark = true }: { size?: number; withWordmark?: boolean }) {
  return (
    <span className="inline-flex items-center gap-2.5">
      <svg width={size} height={size} viewBox="0 0 100 100" aria-hidden>
        <defs>
          <linearGradient id="orb-logo" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stopColor="#6366f1" />
            <stop offset="100%" stopColor="#2563eb" />
          </linearGradient>
        </defs>
        <rect width="100" height="100" rx="24" fill="url(#orb-logo)" />
        <path
          d="M28 34h44v8H28zm0 14h32v8H28zm0 14h40v8H28z"
          fill="white"
          opacity=".94"
        />
      </svg>
      {withWordmark && (
        <span className="font-display text-[17px] font-semibold tracking-tight text-fg">
          Openrow<span className="text-accent">DB</span>
        </span>
      )}
    </span>
  );
}

/* ── Pill — small glass tag ─────────────────────────────────────────────── */
export function Pill({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full border border-hair bg-glass px-3 py-1 text-xs text-muted backdrop-blur ${className}`}
    >
      {children}
    </span>
  );
}

/* ── Btn — primary (gradient) / ghost (glass) ───────────────────────────── */
export function Btn({
  href,
  variant = "primary",
  children,
  className = "",
  ...rest
}: {
  href: string;
  variant?: "primary" | "ghost";
  children: ReactNode;
  className?: string;
} & React.AnchorHTMLAttributes<HTMLAnchorElement>) {
  const base =
    "group relative inline-flex items-center justify-center gap-2 rounded-xl px-5 py-3 text-sm font-medium transition-all duration-300";
  const styles =
    variant === "primary"
      ? "text-white shadow-[0_8px_30px_-8px_rgba(91,124,250,0.7)] hover:shadow-[0_10px_40px_-6px_rgba(91,124,250,0.9)] hover:-translate-y-0.5"
      : "border border-hair bg-glass text-fg backdrop-blur hover:border-hair-2 hover:-translate-y-0.5";
  return (
    <a
      href={href}
      className={`${base} ${styles} ${className}`}
      {...(href.startsWith("http") ? { target: "_blank", rel: "noopener noreferrer" } : {})}
      {...rest}
    >
      {variant === "primary" && (
        <span
          className="absolute inset-0 -z-10 rounded-xl"
          style={{ background: "linear-gradient(120deg,#6366f1,#2f6bff 55%,#38e1d6)" }}
        />
      )}
      {children}
    </a>
  );
}

/* ── Reveal — scroll-into-view fade + rise ──────────────────────────────── */
export function Reveal({
  children,
  delay = 0,
  y = 26,
  className = "",
}: {
  children: ReactNode;
  delay?: number;
  y?: number;
  className?: string;
}) {
  return (
    <motion.div
      className={className}
      initial={{ opacity: 0, y }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-70px" }}
      transition={{ duration: 0.7, delay, ease: [0.16, 1, 0.3, 1] }}
    >
      {children}
    </motion.div>
  );
}

/* ── Section — shared vertical rhythm + anchor ──────────────────────────── */
export function Section({
  id,
  children,
  className = "",
}: {
  id?: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section id={id} className={`relative mx-auto w-full max-w-6xl px-6 py-20 sm:py-28 ${className}`}>
      {children}
    </section>
  );
}

/* ── Ext — external link with safe rel attributes ─────────────────────────── */
export function Ext({
  href,
  children,
  className = "",
  ...rest
}: { href: string; children: ReactNode; className?: string } & React.AnchorHTMLAttributes<HTMLAnchorElement>) {
  return (
    <a href={href} target="_blank" rel="noopener noreferrer" className={className} {...rest}>
      {children}
    </a>
  );
}

/* ── Eyebrow — mono label above section headings ────────────────────────── */
export function Eyebrow({ children }: { children: ReactNode }) {
  return (
    <div className="mb-4 flex items-center gap-3">
      <span className="h-px w-8 bg-gradient-to-r from-accent to-transparent" />
      <span className="eyebrow">{children}</span>
    </div>
  );
}

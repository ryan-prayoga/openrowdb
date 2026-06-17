import { useRef, type ReactNode } from "react";
import { motion, useMotionValue, useSpring, useTransform } from "motion/react";

/* ── SpotlightCard — cursor-tracking radial glow (reactbits-style) ──────── */
export function SpotlightCard({
  children,
  className = "",
  spotlightColor = "rgba(91,124,250,0.22)",
}: {
  children: ReactNode;
  className?: string;
  spotlightColor?: string;
}) {
  const ref = useRef<HTMLDivElement>(null);

  const onMove = (e: React.MouseEvent<HTMLDivElement>) => {
    const el = ref.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    el.style.setProperty("--mx", `${e.clientX - r.left}px`);
    el.style.setProperty("--my", `${e.clientY - r.top}px`);
  };

  return (
    <div
      ref={ref}
      onMouseMove={onMove}
      className={`group relative overflow-hidden ${className}`}
      style={{ ["--spot" as string]: spotlightColor } as React.CSSProperties}
    >
      <div
        className="pointer-events-none absolute -inset-px opacity-0 transition-opacity duration-500 group-hover:opacity-100"
        style={{
          background:
            "radial-gradient(380px circle at var(--mx) var(--my), var(--spot), transparent 62%)",
        }}
      />
      <div className="relative z-10 h-full">{children}</div>
    </div>
  );
}

/* ── TiltedCard — 3D tilt toward the cursor (reactbits-style) ───────────── */
export function TiltedCard({
  children,
  className = "",
  max = 9,
}: {
  children: ReactNode;
  className?: string;
  max?: number;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const px = useMotionValue(0);
  const py = useMotionValue(0);
  const rx = useSpring(useTransform(py, [-0.5, 0.5], [max, -max]), { stiffness: 140, damping: 16 });
  const ry = useSpring(useTransform(px, [-0.5, 0.5], [-max, max]), { stiffness: 140, damping: 16 });

  const onMove = (e: React.MouseEvent) => {
    const el = ref.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    px.set((e.clientX - r.left) / r.width - 0.5);
    py.set((e.clientY - r.top) / r.height - 0.5);
  };
  const reset = () => {
    px.set(0);
    py.set(0);
  };

  return (
    <motion.div
      ref={ref}
      onMouseMove={onMove}
      onMouseLeave={reset}
      style={{ rotateX: rx, rotateY: ry, transformPerspective: 1200 }}
      className={`[transform-style:preserve-3d] ${className}`}
    >
      {children}
    </motion.div>
  );
}

import { useState } from "react";
import { TiltedCard } from "../bits/cards";

/*
 * ScreenshotFrame — a tilted glass window frame sized 16:10 for a real app
 * screenshot. Pass `src` to show a real capture; if the file is missing (or
 * fails to load) it gracefully falls back to a labelled placeholder preview.
 *
 * To add real shots: drop PNGs into web/public/shots/ (browse.png, query.png,
 * structure.png) — Showcase already points each frame at them.
 */
export function ScreenshotFrame({
  title,
  caption,
  src,
  accent = "#5b7cfa",
}: {
  title: string;
  caption: string;
  src?: string;
  accent?: string;
}) {
  const [failed, setFailed] = useState(false);
  const showImage = src && !failed;

  return (
    <TiltedCard className="h-full">
      <figure className="glass glass-hover h-full overflow-hidden rounded-[var(--radius-glass)]">
        {/* window chrome */}
        <div className="flex items-center gap-2 border-b border-hair bg-white/[0.03] px-4 py-2.5">
          <span className="h-2.5 w-2.5 rounded-full bg-[#ff5f57]" />
          <span className="h-2.5 w-2.5 rounded-full bg-[#febc2e]" />
          <span className="h-2.5 w-2.5 rounded-full bg-[#28c840]" />
          <span className="ml-2 font-mono text-[10px] text-faint">{title}</span>
        </div>

        {/* body — real screenshot if available, else placeholder preview */}
        <div className="relative aspect-[16/10] w-full overflow-hidden">
          {showImage ? (
            <img
              src={src}
              alt={caption}
              loading="lazy"
              onError={() => setFailed(true)}
              className="h-full w-full object-cover object-top"
            />
          ) : (
            <div
              className="absolute inset-0"
              style={{
                background: `radial-gradient(120% 90% at 0% 0%, ${accent}22, transparent 55%), linear-gradient(180deg,#0a0c13,#070810)`,
              }}
            >
              {/* abstract preview bars so the slot never looks empty */}
              <div className="absolute inset-0 flex gap-3 p-5">
                <div className="hidden w-1/4 flex-col gap-2 sm:flex">
                  {[0.9, 0.6, 0.7, 0.5, 0.8].map((w, i) => (
                    <div
                      key={i}
                      className="h-2.5 rounded bg-white/10"
                      style={{ width: `${w * 100}%` }}
                    />
                  ))}
                </div>
                <div className="flex-1 space-y-2">
                  {[0.95, 0.8, 0.88, 0.6, 0.92, 0.7, 0.84].map((w, i) => (
                    <div
                      key={i}
                      className="h-3 rounded"
                      style={{
                        width: `${w * 100}%`,
                        background: i === 0 ? `${accent}55` : "rgba(255,255,255,0.06)",
                      }}
                    />
                  ))}
                </div>
              </div>
            </div>
          )}
        </div>

        <figcaption className="border-t border-hair px-4 py-3 text-sm text-muted">
          {caption}
        </figcaption>
      </figure>
    </TiltedCard>
  );
}

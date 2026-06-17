import { useEffect, useState } from "react";
import { Logo } from "../ui/primitives";
import { Ext } from "../ui/primitives";
import { links } from "../../data/platforms";

// Absolute (/#...) so they also work from the /changelog page.
const navLinks = [
  ["Features", "/#features"],
  ["Showcase", "/#showcase"],
  ["Platforms", "/#platforms"],
  ["Changelog", "/changelog"],
];

export function Nav() {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 12);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <header className="fixed inset-x-0 top-0 z-50 flex flex-col items-center px-4 pt-4">
      <nav
        className={`flex w-full max-w-5xl items-center justify-between rounded-2xl px-4 py-2.5 transition-all duration-300 ${
          scrolled || open ? "glass" : "border border-transparent"
        }`}
      >
        <a href="/" aria-label="OpenrowDB home">
          <Logo />
        </a>

        <div className="hidden items-center gap-1 md:flex">
          {navLinks.map(([label, href]) => (
            <a
              key={href}
              href={href}
              className="rounded-lg px-3 py-1.5 text-sm text-muted transition-colors hover:text-fg"
            >
              {label}
            </a>
          ))}
        </div>

        <div className="flex items-center gap-2">
          <Ext
            href={links.repo}
            className="hidden rounded-lg px-3 py-1.5 text-sm text-muted transition-colors hover:text-fg sm:block"
          >
            GitHub
          </Ext>
          <Ext
            href={links.releasesLatest}
            className="relative inline-flex items-center gap-1.5 rounded-lg px-4 py-1.5 text-sm font-medium text-white"
          >
            <span
              className="absolute inset-0 -z-10 rounded-lg"
              style={{ background: "linear-gradient(120deg,#6366f1,#2f6bff 60%,#38e1d6)" }}
            />
            Download
          </Ext>

          {/* Mobile menu toggle */}
          <button
            type="button"
            aria-label="Toggle menu"
            aria-expanded={open}
            onClick={() => setOpen((v) => !v)}
            className="ml-1 inline-flex h-9 w-9 items-center justify-center rounded-lg border border-hair bg-glass text-fg md:hidden"
          >
            <span className="relative block h-3.5 w-4">
              <span
                className={`absolute left-0 block h-0.5 w-4 bg-current transition-all ${
                  open ? "top-1.5 rotate-45" : "top-0"
                }`}
              />
              <span
                className={`absolute left-0 top-1.5 block h-0.5 w-4 bg-current transition-all ${
                  open ? "opacity-0" : "opacity-100"
                }`}
              />
              <span
                className={`absolute left-0 block h-0.5 w-4 bg-current transition-all ${
                  open ? "top-1.5 -rotate-45" : "top-3"
                }`}
              />
            </span>
          </button>
        </div>
      </nav>

      {/* Mobile dropdown — opaque panel so content behind doesn't bleed through */}
      {open && (
        <div
          className="mt-2 w-full max-w-5xl rounded-2xl border border-hair p-2 shadow-[0_24px_80px_-20px_rgba(0,0,0,0.8)] backdrop-blur-xl md:hidden"
          style={{ background: "rgba(9, 11, 18, 0.96)" }}
        >
          {[...navLinks, ["GitHub", links.repo]].map(([label, href]) =>
            href.startsWith("http") ? (
              <Ext
                key={href}
                href={href}
                onClick={() => setOpen(false)}
                className="block rounded-lg px-4 py-3 text-sm text-muted transition-colors hover:bg-white/[0.05] hover:text-fg"
              >
                {label}
              </Ext>
            ) : (
              <a
                key={href}
                href={href}
                onClick={() => setOpen(false)}
                className="block rounded-lg px-4 py-3 text-sm text-muted transition-colors hover:bg-white/[0.05] hover:text-fg"
              >
                {label}
              </a>
            )
          )}
        </div>
      )}
    </header>
  );
}

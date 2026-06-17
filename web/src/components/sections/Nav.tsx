import { useEffect, useState } from "react";
import { Logo } from "../ui/primitives";
import { links } from "../../data/platforms";

const navLinks = [
  ["Features", "#features"],
  ["Showcase", "#showcase"],
  ["Platforms", "#platforms"],
  ["Install", "#install"],
];

export function Nav() {
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 12);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <header className="fixed inset-x-0 top-0 z-50 flex justify-center px-4 pt-4">
      <nav
        className={`flex w-full max-w-5xl items-center justify-between rounded-2xl px-4 py-2.5 transition-all duration-300 ${
          scrolled ? "glass" : "border border-transparent"
        }`}
      >
        <a href="#top" aria-label="OpenrowDB home">
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
          <a
            href={links.repo}
            className="hidden rounded-lg px-3 py-1.5 text-sm text-muted transition-colors hover:text-fg sm:block"
          >
            GitHub
          </a>
          <a
            href={links.releasesLatest}
            className="relative inline-flex items-center gap-1.5 rounded-lg px-4 py-1.5 text-sm font-medium text-white"
          >
            <span
              className="absolute inset-0 -z-10 rounded-lg"
              style={{ background: "linear-gradient(120deg,#6366f1,#2f6bff 60%,#38e1d6)" }}
            />
            Download
          </a>
        </div>
      </nav>
    </header>
  );
}

import { Logo } from "../ui/primitives";
import { links } from "../../data/platforms";

export function Footer() {
  return (
    <footer className="relative mt-10 border-t border-hair">
      <div className="mx-auto flex w-full max-w-6xl flex-col items-start justify-between gap-8 px-6 py-12 sm:flex-row sm:items-center">
        <div>
          <Logo />
          <p className="mt-3 max-w-xs text-sm text-faint">
            A modern, native database client — open source from day one.
          </p>
        </div>

        <div className="flex flex-wrap gap-x-8 gap-y-2 text-sm">
          <a href="#features" className="text-muted transition-colors hover:text-fg">
            Features
          </a>
          <a href="#install" className="text-muted transition-colors hover:text-fg">
            Install
          </a>
          <a href={links.releases} className="text-muted transition-colors hover:text-fg">
            Releases
          </a>
          <a href={links.repo} className="text-muted transition-colors hover:text-fg">
            GitHub
          </a>
          <a href={links.x} className="text-muted transition-colors hover:text-fg">
            X / Twitter
          </a>
        </div>
      </div>

      <div className="border-t border-hair">
        <div className="mx-auto flex w-full max-w-6xl items-center justify-between px-6 py-5 text-xs text-faint">
          <span>MIT © 2026 Ryan Prayoga</span>
          <span>Made with 🇮🇩 in Indonesia</span>
        </div>
      </div>
    </footer>
  );
}

# OpenrowDB — marketing site

The landing page for [openrowdb.ryanprayoga.dev](https://openrowdb.ryanprayoga.dev).

**Stack:** Vite + React + TypeScript · Tailwind v4 (CSS-first) · [ReactBits](https://reactbits.dev)-style
animated components (`motion`, `gsap`, `ogl`). Design language: macOS "Liquid Glass" — animated
WebGL aurora, frosted glass panels, indigo→blue + electric-cyan.

## Develop

```bash
cd web
npm install
npm run dev        # http://localhost:5173
```

## Build & preview

```bash
npm run build      # → static web/dist/
npm run preview    # serve the production build locally
```

## Deploy

`npm run build` emits a fully static `web/dist/`. Point the host serving
`openrowdb.ryanprayoga.dev` at `web/dist/`.

- The site is static — any static host works (Cloudflare Pages, Netlify, GitHub Pages, S3…).
- **Keep `/install.sh` resolving on the domain.** It is served separately (not part of this
  build); the hero/install copy command depends on `https://openrowdb.ryanprayoga.dev/install.sh`.
- The legacy single-file page at `apps/mac/site/index.html` is kept until this build is live —
  remove it once the domain points here.

## Layout

```
src/
  components/
    bits/        # ReactBits-style: Aurora (WebGL), text (Split/Shiny/Gradient/CountUp), cards (Spotlight/Tilted)
    ui/          # Logo, Pill, Btn, Reveal, Section, AppWindowFrame, ScreenshotFrame, InstallCommand
    sections/    # Nav, Hero, Why, Pillars, Showcase, Platforms, Install, OpenSource, Footer
  data/          # features.ts + platforms.ts — copy sourced from ROADMAP.md / README.md
  lib/           # useReducedMotion
  index.css      # Tailwind import + @theme tokens + glass/grain atoms
```

## Notes

- All feature copy is sourced from the repo's `ROADMAP.md` / `README.md`. When features ship,
  update `src/data/*` — do not list unshipped work.
- `ScreenshotFrame` renders placeholders. Drop real app PNGs in via its `src` prop
  (search `TODO(screenshots)`).
- Motion respects `prefers-reduced-motion` (Aurora WebGL disabled → static gradient fallback).
- Fonts load from Fontshare (Clash Display, Satoshi) + Google Fonts (JetBrains Mono) in `index.html`.

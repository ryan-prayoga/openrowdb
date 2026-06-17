import { Nav } from "./components/sections/Nav";
import { Hero } from "./components/sections/Hero";
import { Why } from "./components/sections/Why";
import { Pillars } from "./components/sections/Pillars";
import { Showcase } from "./components/sections/Showcase";
import { Platforms } from "./components/sections/Platforms";
import { Install } from "./components/sections/Install";
import { OpenSource } from "./components/sections/OpenSource";
import { Footer } from "./components/sections/Footer";

export default function App() {
  return (
    <div className="grain relative min-h-screen bg-ink">
      <Nav />
      <main>
        <Hero />
        <Why />
        <Pillars />
        <Showcase />
        <Platforms />
        <Install />
        <OpenSource />
      </main>
      <Footer />
    </div>
  );
}

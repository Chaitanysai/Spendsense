import { useEffect, useState } from "react";import { Nav } from "./components/Nav";
import { Hero } from "./components/Hero";
import { Product } from "./components/Product";
import { Features } from "./components/Features";
import { HowItWorks } from "./components/HowItWorks";
import { Privacy } from "./components/Privacy";
import { FinalCTA, Footer } from "./components/Footer";
import { useReducedMotion } from "./hooks";

/**
 * Counting preloader, as the reference opens.
 *
 * It does not wait on network: the page content is already in the bundle, so
 * this is a short authored entrance rather than a loading gate. It resolves on
 * a timer and is skipped entirely under reduced motion, so no one is ever held
 * behind an animation they did not ask for.
 */
function Preloader({ onDone }: { onDone: () => void }) {
  const [pct, setPct] = useState(0);
  const reduced = useReducedMotion();

  useEffect(() => {
    if (reduced) {
      onDone();
      return;
    }
    const start = performance.now();
    const dur = 1150;
    let raf = 0;
    const tick = () => {
      const t = Math.min((performance.now() - start) / dur, 1);
      // Count fast, then settle, so it reads as a readout rather than a bar.
      const eased = 1 - Math.pow(1 - t, 2.4);
      setPct(Math.round(eased * 100));
      if (t < 1) raf = requestAnimationFrame(tick);
      else setTimeout(onDone, 160);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [reduced, onDone]);

  if (reduced) return null;

  return (
    <div className="preload" aria-hidden="true">
      <div className="preload__mark">
        <svg viewBox="0 0 24 24" fill="none">
          <path
            d="M4 15.5 9.2 8l4 5.2L15.4 10 20 15.5"
            stroke="currentColor"
            strokeWidth="1.6"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
          <circle cx="9.2" cy="8" r="1.6" fill="currentColor" />
        </svg>
      </div>
      <div className="preload__count mono">{String(pct).padStart(3, "0")}</div>
      <div className="preload__bar">
        <span style={{ transform: `scaleX(${pct / 100})` }} />
      </div>
    </div>
  );
}

export default function App() {
  const [ready, setReady] = useState(false);

  // Deep links: the browser tries to scroll to #hash before React has mounted the
  // target, so the jump silently fails. Re-apply it once the page exists.
  useEffect(() => {
    const hash = window.location.hash.slice(1);
    if (!hash) return;
    const el = document.getElementById(hash);
    if (!el) return;
    // Wait for layout to settle so the target's final position is known.
    const id = window.setTimeout(() => {
      el.scrollIntoView({ behavior: "auto", block: "start" });
    }, 60);
    return () => window.clearTimeout(id);
  }, []);

  return (
    <>
      {!ready && <Preloader onDone={() => setReady(true)} />}
      <div className={`page${ready ? " is-ready" : ""}`}>
        <Nav />
        <main id="main">
          <Hero />
          <Product />
          <Features />
          <HowItWorks />
          <Privacy />
          <FinalCTA />
        </main>
        <Footer />
      </div>
    </>
  );
}

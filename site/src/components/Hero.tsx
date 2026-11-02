import { useEffect, useRef } from "react";
import { HeroScene } from "./HeroScene";

/**
 * The hero.
 *
 * Composition follows the reference: full-bleed atmospheric scene, navigation
 * floating above it, a small bracketed eyebrow at the lower left, a very large
 * display headline occupying the left half, supporting copy and two CTAs at the
 * lower right sitting over the scene's water line.
 *
 * Scroll drives one value — how far the hero has left — which the WebGL scene
 * reads to order the particle cloud and the CSS reads to fade the copy.
 */
export function Hero() {
  const sectionRef = useRef<HTMLElement>(null);
  const progress = useRef(0);

  useEffect(() => {
    const el = sectionRef.current;
    if (!el) return;
    let raf = 0;
    const update = () => {
      const h = el.offsetHeight || 1;
      progress.current = Math.min(Math.max(window.scrollY / h, 0), 1);
      raf = 0;
    };
    const onScroll = () => {
      if (!raf) raf = requestAnimationFrame(update);
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    update();
    return () => {
      window.removeEventListener("scroll", onScroll);
      if (raf) cancelAnimationFrame(raf);
    };
  }, []);

  return (
    <section className="hero" id="top" ref={sectionRef}>
      <div className="hero__scene">
        <HeroScene progressRef={progress} />
        <div className="hero__vignette" aria-hidden="true" />
        <div className="hero__grain" aria-hidden="true" />
      </div>

      <div className="hero__content shell">
        <span className="eyebrow">
          <i aria-hidden="true" />
          Expense intelligence
        </span>

        <div className="hero__foot">
          <h1 className="display">
            Your money.
            <br />
            Your clarity.
            <br />
            <em>Your control.</em>
          </h1>

          <div className="hero__aside">
            <p>
              Understand your spending, discover patterns, and take control of
              your financial life with SpendSense.
            </p>
            <div className="hero__ctas">
              <a className="btn btn--primary" href="#install">
                Get started
                <svg viewBox="0 0 16 16" aria-hidden="true" width="14" height="14">
                  <path
                    d="M3 8h9M8.5 4l4 4-4 4"
                    stroke="currentColor"
                    strokeWidth="1.8"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    fill="none"
                  />
                </svg>
              </a>
              <a className="btn btn--glass" href="#product">
                Explore SpendSense
              </a>
            </div>
            <p className="hero__meta">
              Free · Android 7.0+ · No bank login
            </p>
          </div>
        </div>
      </div>

      <div className="hero__scroll" aria-hidden="true">
        <span>Scroll</span>
        <i />
      </div>
    </section>
  );
}

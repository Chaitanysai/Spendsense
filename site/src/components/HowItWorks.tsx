import { useEffect, useRef, useState } from "react";
import { useReducedMotion } from "../hooks";

/**
 * How it works, as a scrubbed progression rather than a row of columns.
 *
 * The four steps advance as the section passes the middle of the viewport; a
 * single rail fills behind them. Scroll drives a ref, not React state, and a
 * single state write happens only when the active step actually changes.
 */
const STEPS = [
  {
    n: "01",
    title: "Capture",
    body: "SpendSense reads debit and credit SMS already in your inbox. Nothing is fetched from your bank and no login is created.",
  },
  {
    n: "02",
    title: "Organise",
    body: "Each message is parsed on the device into amount, merchant, bank and category, then stored in an encrypted local ledger.",
  },
  {
    n: "03",
    title: "Understand",
    body: "Category breakdowns, weekly activity and month-over-month movement are computed from your own rows, not from a model's guess.",
  },
  {
    n: "04",
    title: "Decide",
    body: "Set a cycle and per-category limits, and let the budget alarm reach you before the money is gone.",
  },
] as const;

export function HowItWorks() {
  const sectionRef = useRef<HTMLElement>(null);
  const railRef = useRef<HTMLDivElement>(null);
  const [active, setActive] = useState(0);
  const reduced = useReducedMotion();

  useEffect(() => {
    const section = sectionRef.current;
    const rail = railRef.current;
    if (!section || !rail) return;

    let raf = 0;
    const update = () => {
      raf = 0;
      const r = section.getBoundingClientRect();
      const vh = window.innerHeight;
      // 0 when the section top reaches 85% of the viewport, 1 when its bottom
      // reaches 25%. Outside that the value is clamped.
      const total = r.height + vh * 0.6;
      const passed = vh * 0.85 - r.top;
      const p = Math.min(Math.max(passed / total, 0), 1);
      rail.style.setProperty("--p", String(p));
      const next = Math.min(STEPS.length - 1, Math.floor(p * STEPS.length));
      setActive((prev) => (prev === next ? prev : next));
    };
    const onScroll = () => {
      if (!raf) raf = requestAnimationFrame(update);
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);
    update();
    return () => {
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onScroll);
      if (raf) cancelAnimationFrame(raf);
    };
  }, []);

  return (
    <section
      className={`section how${reduced ? " how--static" : ""}`}
      id="how"
      ref={sectionRef}
    >
      <div className="shell how__grid">
        <div className="how__sticky">
          <span className="kicker">How it works</span>
          <h2 className="h2">
            Four steps,
            <br />
            <span className="muted">all on the device.</span>
          </h2>

          <div className="how__rail" ref={railRef} aria-hidden="true">
            <span className="how__rail-fill" />
            {STEPS.map((s, i) => (
              <span
                key={s.n}
                className={`how__tick${i <= active ? " is-on" : ""}`}
                style={{ top: `${(i / (STEPS.length - 1)) * 100}%` }}
              >
                {s.n}
              </span>
            ))}
          </div>
        </div>

        <ol className="how__steps">
          {STEPS.map((s, i) => (
            <li
              key={s.n}
              className={`how__step${i === active ? " is-active" : ""}`}
            >
              <span className="how__n mono">{s.n}</span>
              <div>
                <h3 className="h3">{s.title}</h3>
                <p>{s.body}</p>
              </div>
            </li>
          ))}
        </ol>
      </div>
    </section>
  );
}

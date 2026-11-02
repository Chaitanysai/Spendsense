import { useEffect, useRef, useState } from "react";

/** True when the user asked the OS to reduce motion. Subscribes to changes. */
export function useReducedMotion(): boolean {
  const [reduced, setReduced] = useState(() =>
    typeof window !== "undefined"
      ? window.matchMedia("(prefers-reduced-motion: reduce)").matches
      : false
  );
  useEffect(() => {
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    const on = () => setReduced(mq.matches);
    mq.addEventListener("change", on);
    return () => mq.removeEventListener("change", on);
  }, []);
  return reduced;
}

/**
 * Reveals an element once when it first crosses into view. Adds `is-in` and
 * disconnects, so the observer does not run for the life of the page.
 */
export function useReveal<T extends HTMLElement>(
  threshold = 0.15
): { ref: React.RefObject<T>; revealed: boolean } {
  const ref = useRef<T>(null);
  const [revealed, setRevealed] = useState(false);

  useEffect(() => {
    // Reveal is progressive enhancement: the stylesheet only hides elements once
    // this class exists, so a browser without IntersectionObserver, or a failure
    // below, leaves the page fully readable rather than blank.
    if (typeof IntersectionObserver === "undefined") {
      setRevealed(true);
      return;
    }
    document.documentElement.classList.add("js-reveal");

    const el = ref.current;
    if (!el) {
      setRevealed(true);
      return;
    }
    const io = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) {
          setRevealed(true);
          io.disconnect();
        }
      },
      { threshold, rootMargin: "0px 0px -6% 0px" }
    );
    io.observe(el);

    return () => io.disconnect();
  }, [threshold]);

  return { ref, revealed };
}

/** Window scroll position, throttled to one update per frame. */
export function useScrollY(): number {
  const [y, setY] = useState(0);
  useEffect(() => {
    let frame = 0;
    const onScroll = () => {
      if (frame) return;
      frame = requestAnimationFrame(() => {
        setY(window.scrollY);
        frame = 0;
      });
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    onScroll();
    return () => {
      window.removeEventListener("scroll", onScroll);
      if (frame) cancelAnimationFrame(frame);
    };
  }, []);
  return y;
}

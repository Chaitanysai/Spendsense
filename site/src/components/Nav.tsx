import { useEffect, useState } from "react";
import { useScrollY } from "../hooks";

const LINKS = [
  { label: "Product", href: "#product" },
  { label: "Features", href: "#features" },
  { label: "How it works", href: "#how" },
  { label: "Privacy", href: "#privacy" },
];

export function Nav() {
  const y = useScrollY();
  const [open, setOpen] = useState(false);
  const scrolled = y > 24;

  // Close on Escape and lock the page behind the mobile sheet.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  useEffect(() => {
    document.body.style.overflow = open ? "hidden" : "";
    return () => {
      document.body.style.overflow = "";
    };
  }, [open]);

  return (
    <>
      <header className={`nav${scrolled ? " nav--scrolled" : ""}`}>
        <div className="nav__shell">
          <a className="brand" href="#top" aria-label="SpendSense home">
            <span className="brand__mark" aria-hidden="true">
              <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
                <path
                  d="M4 15.5 9.2 8l4 5.2L15.4 10 20 15.5"
                  stroke="currentColor"
                  strokeWidth="1.9"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                />
                <circle cx="9.2" cy="8" r="1.9" fill="currentColor" />
              </svg>
            </span>
            <span className="brand__word">SpendSense</span>
          </a>

          <nav className="nav__pill" aria-label="Primary">
            {LINKS.map((l) => (
              <a key={l.href} href={l.href}>
                {l.label}
              </a>
            ))}
          </nav>

          <div className="nav__actions">
            <a className="btn btn--ghost btn--sm" href="#install">
              Sign in
            </a>
            <a className="btn btn--primary btn--sm" href="#install">
              Get started
            </a>
          </div>

          <button
            className="nav__toggle"
            type="button"
            aria-expanded={open}
            aria-controls="mobile-menu"
            aria-label={open ? "Close menu" : "Open menu"}
            onClick={() => setOpen((v) => !v)}
          >
            <span className={`nav__bars${open ? " is-open" : ""}`} aria-hidden="true">
              <i />
              <i />
            </span>
          </button>
        </div>
      </header>

      <div
        id="mobile-menu"
        className={`sheet${open ? " sheet--open" : ""}`}
        hidden={!open}
      >
        <nav aria-label="Mobile">
          {LINKS.map((l) => (
            <a key={l.href} href={l.href} onClick={() => setOpen(false)}>
              {l.label}
            </a>
          ))}
        </nav>
        <a className="btn btn--primary" href="#install" onClick={() => setOpen(false)}>
          Get started
        </a>
        <p className="sheet__note">Free · Android 7.0+ · No account required</p>
      </div>
    </>
  );
}

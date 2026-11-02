import { useReveal } from "../hooks";

/** Final conversion section and footer. */
export function FinalCTA() {
  const { ref, revealed } = useReveal<HTMLDivElement>();

  return (
    <section className="section cta" id="install">
      <div className="shell">
        <div className={`cta__panel glass reveal${revealed ? " is-in" : ""}`} ref={ref}>
          <div className="cta__beam" aria-hidden="true" />
          <span className="kicker">Install</span>
          <h2 className="h2 cta__title">
            Start with the messages
            <br />
            <span className="muted">you already have.</span>
          </h2>
          <p className="lede cta__lede">
            Download the signed APK, install it, and grant SMS access once. The
            ledger builds itself from there.
          </p>

          <div className="cta__actions">
            <a
              className="btn btn--primary btn--lg"
              href="https://github.com/Chaitanysai/Spendsense/releases/latest"
            >
              Download APK
              <svg viewBox="0 0 16 16" aria-hidden="true" width="15" height="15">
                <path
                  d="M8 3v8m0 0 3.2-3.2M8 11 4.8 7.8M3 13.5h10"
                  stroke="currentColor"
                  strokeWidth="1.8"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  fill="none"
                />
              </svg>
            </a>
            <a className="btn btn--glass btn--lg" href="/legal/">
              Read the privacy policy
            </a>
          </div>

          <ul className="cta__facts">
            <li>Android 7.0 or newer</li>
            <li>Side-loaded, not from Google Play</li>
            <li>Free · no ads · no subscription</li>
          </ul>
        </div>
      </div>
    </section>
  );
}

export function Footer() {
  return (
    <footer className="foot">
      <div className="shell foot__grid">
        <div className="foot__brand">
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
          <p className="foot__tag">
            Offline-first expense tracking for bank and UPI SMS.
          </p>
        </div>

        <nav className="foot__col" aria-label="Product">
          <h3>Product</h3>
          <a href="#features">Features</a>
          <a href="#how">How it works</a>
          <a href="#privacy">Privacy</a>
          <a href="#install">Install</a>
        </nav>

        <nav className="foot__col" aria-label="Legal">
          <h3>Legal</h3>
          <a href="/legal/#privacy">Privacy policy</a>
          <a href="/legal/#terms">Terms</a>
          <a href="/legal/#refunds">Refunds</a>
          <a href="/legal/#cookies">Cookies</a>
        </nav>

        <nav className="foot__col" aria-label="Source">
          <h3>Source</h3>
          <a href="https://github.com/Chaitanysai/Spendsense">GitHub</a>
          <a href="https://github.com/Chaitanysai/Spendsense/releases">Releases</a>
          <a href="/legal/#contact">Contact</a>
        </nav>
      </div>

      <div className="shell foot__base">
        <span>© 2026 SpendSense · Chaitanya Sai Kandula</span>
        <span className="foot__note">
          Not financial advice. SpendSense records and totals; it does not advise.
        </span>
      </div>
    </footer>
  );
}

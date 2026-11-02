import { useReveal } from "../hooks";

/**
 * Features. Numbered glass cards, following the reference's 01–04 treatment,
 * extended to six. Every line corresponds to a service that exists in the
 * codebase; nothing here is aspirational.
 */
const FEATURES = [
  {
    n: "01",
    title: "Reads the SMS you already have",
    body: "Debit and credit messages from your bank and UPI apps are parsed on the device into amount, merchant, bank and category.",
    icon: (
      <>
        <rect x="3" y="5" width="18" height="14" rx="2.5" />
        <path d="M7 10h7M7 14h10" />
      </>
    ),
  },
  {
    n: "02",
    title: "Encrypted where it lives",
    body: "An AES-256-GCM ledger on your phone. The key is held by the Android Keystore, not written into the database and not stored on a server.",
    icon: (
      <>
        <rect x="4" y="10" width="16" height="10" rx="2.5" />
        <path d="M8 10V7a4 4 0 1 1 8 0v3" />
      </>
    ),
  },
  {
    n: "03",
    title: "Budgets that warn early",
    body: "A monthly cycle, per-category limits and thresholds you set, with an alarm before the money is gone rather than after.",
    icon: (
      <>
        <circle cx="12" cy="12" r="9" />
        <path d="M12 7.5V12l3 2" />
      </>
    ),
  },
  {
    n: "04",
    title: "Insights from your own rows",
    body: "Category breakdown, seven-day activity and month-over-month comparison, computed from the entries in your ledger.",
    icon: (
      <>
        <path d="M4 19V7m0 12h16M8 19v-7m4 7V5m4 14v-5" />
      </>
    ),
  },
  {
    n: "05",
    title: "Bills and recurring payments",
    body: "Repeat payments are detected and grouped, so subscriptions and bills you have already committed to stay visible.",
    icon: (
      <>
        <path d="M4 6h16M4 12h16M4 18h10" />
        <circle cx="18" cy="18" r="2.4" />
      </>
    ),
  },
  {
    n: "06",
    title: "Yours to take with you",
    body: "Export the whole ledger as JSON at any time, delete individual rows, or clear the database completely.",
    icon: (
      <>
        <path d="M12 4v11m0 0 4-4m-4 4-4-4M5 19h14" />
      </>
    ),
  },
] as const;

export function Features() {
  const { ref, revealed } = useReveal<HTMLDivElement>(0.08);

  return (
    <section className="section features" id="features">
      <div className="shell">
        <header className="section__head">
          <span className="kicker">Capabilities</span>
          <h2 className="h2">Built from what the phone already holds</h2>
        </header>

        <div className={`features__grid reveal${revealed ? " is-in" : ""}`} ref={ref}>
          {FEATURES.map((f, i) => (
            <article
              className="feature glass"
              key={f.n}
              style={{ transitionDelay: `${i * 70}ms` }}
            >
              <div className="feature__top">
                <span className="feature__icon" aria-hidden="true">
                  <svg
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="1.6"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  >
                    {f.icon}
                  </svg>
                </span>
                <span className="feature__n mono">{f.n}</span>
              </div>
              <h3 className="h3">{f.title}</h3>
              <p>{f.body}</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

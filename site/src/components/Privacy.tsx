import { useReveal } from "../hooks";

/**
 * Privacy and security.
 *
 * Every statement here is checkable against the implementation and is phrased
 * as a fact about what the app does or does not contain, never as a guarantee.
 * The refusal list is load-bearing: it is the section a sceptical visitor reads
 * to decide whether to install.
 */
const POINTS = [
  {
    title: "On-device parsing",
    body: "SMS is read and parsed locally. No parsing request is sent anywhere unless you switch on AI-assisted parsing yourself.",
  },
  {
    title: "Encrypted ledger",
    body: "AES-256-GCM at rest, with the key held by the Android Keystore rather than written beside the database.",
  },
  {
    title: "Off by default",
    body: "Account sync, AI parsing, the assistant and Gmail import are each disabled until you enable them individually.",
  },
] as const;

const REFUSES = [
  "No bank login, card number or UPI PIN is ever requested.",
  "No advertising SDK and no ad network in the build.",
  "No analytics or crash-reporting SDK.",
  "No data sale.",
  "No subscription and no paywall on your own history.",
] as const;

export function Privacy() {
  const { ref, revealed } = useReveal<HTMLDivElement>();

  return (
    <section className="section privacy" id="privacy">
      <div className="shell">
        <div className={`privacy__grid reveal${revealed ? " is-in" : ""}`} ref={ref}>
          <header className="privacy__head">
            <span className="kicker">Privacy &amp; security</span>
            <h2 className="h2">
              It asks for less
              <br />
              <span className="muted">than you expect.</span>
            </h2>
            <p className="lede">
              SpendSense is built around a single constraint: the data does not
              need to leave the phone, so it does not.
            </p>
            <dl className="privacy__facts">
              <div>
                <dt>Ledger</dt>
                <dd>AES-256-GCM, on device</dd>
              </div>
              <div>
                <dt>Key</dt>
                <dd>Android Keystore</dd>
              </div>
              <div>
                <dt>Network</dt>
                <dd>Not required to record</dd>
              </div>
              <div>
                <dt>Cloud features</dt>
                <dd>Each off until enabled</dd>
              </div>
            </dl>
          </header>

          <div className="privacy__cards">
            {POINTS.map((p) => (
              <article className="privacy__card glass" key={p.title}>
                <h3 className="h3">{p.title}</h3>
                <p>{p.body}</p>
              </article>
            ))}
          </div>

          <div className="privacy__refuse glass">
            <h3 className="privacy__refuse-title">What it refuses to do</h3>
            <ul>
              {REFUSES.map((r) => (
                <li key={r}>
                  <span className="privacy__x" aria-hidden="true">
                    <svg viewBox="0 0 12 12" width="10" height="10">
                      <path
                        d="M2.5 2.5l7 7M9.5 2.5l-7 7"
                        stroke="currentColor"
                        strokeWidth="1.7"
                        strokeLinecap="round"
                      />
                    </svg>
                  </span>
                  {r}
                </li>
              ))}
            </ul>
            <p className="privacy__note">
              Read the{" "}
              <a href="/legal/#privacy">privacy policy</a> and{" "}
              <a href="/legal/#terms">terms</a>.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}

import { useReveal } from "../hooks";

/**
 * "Product" — the mechanism, set as a large statement with a floating glass
 * specimen beside it. This is the section that has to carry the argument, so it
 * gets the most typographic weight after the hero.
 */
export function Product() {
  const { ref, revealed } = useReveal<HTMLDivElement>();

  return (
    <section className="section product" id="product">
      <div className="shell">
        <div className={`product__grid reveal${revealed ? " is-in" : ""}`} ref={ref}>
          <div className="product__lede">
            <span className="kicker">The mechanism</span>
            <h2 className="h2">
              The record is already on your phone.
              <span className="muted"> SpendSense reads it.</span>
            </h2>
            <p className="lede">
              Every UPI payment, card swipe and account debit has already been
              delivered to you as an SMS. SpendSense parses what is already
              there, on the device, and keeps the result encrypted.
            </p>
            <p className="lede muted-sm">
              That is why there is no bank login, no aggregator, and no reason
              for the data to leave the phone.
            </p>
          </div>

          {/* A glass specimen of a parsed transaction. Values are illustrative
              and labelled as such in the caption, never presented as a real
              customer record. */}
          <figure className="specimen glass">
            <div className="specimen__head">
              <span className="specimen__dot" aria-hidden="true" />
              <span>Parsed on device</span>
              <span className="specimen__time">just now</span>
            </div>

            <dl className="specimen__rows">
              <div>
                <dt>Amount</dt>
                <dd className="mono">₹ 349.00</dd>
              </div>
              <div>
                <dt>Merchant</dt>
                <dd>Blue Tokai Coffee</dd>
              </div>
              <div>
                <dt>Category</dt>
                <dd>
                  <span className="chip">Food &amp; drink</span>
                </dd>
              </div>
              <div>
                <dt>Source</dt>
                <dd>
                  <span className="chip chip--quiet">SMS</span>
                  <span className="chip chip--quiet">HDFC</span>
                </dd>
              </div>
            </dl>

            <figcaption className="specimen__cap">
              Illustrative example, not a customer record.
            </figcaption>
          </figure>
        </div>
      </div>
    </section>
  );
}

import { expect } from "@open-wc/testing";

import { localizeCurrencyElements, localizeCurrencyLabel } from "/static/js/common/currency.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("common currency", () => {
  afterEach(() => {
    // Reset the document fixture after every test.
    resetDom();
  });

  it("formats currency codes with locale-specific symbols", () => {
    // Format server currency labels with a deterministic locale.
    const localizedUsd = localizeCurrencyLabel("USD 5.00", "en-GB");
    const localizedEur = localizeCurrencyLabel("From EUR 20.00", "en-GB");

    // Verify currency codes are replaced with locale-specific symbols.
    expect(localizedUsd).to.equal("US$5.00");
    expect(localizedEur).to.equal("From €20.00");
  });

  it("preserves labels that are not server currency amounts", () => {
    // Pass non-currency labels through the localization helper.
    const freeLabel = localizeCurrencyLabel("Free", "en-GB");
    const emptyLabel = localizeCurrencyLabel("", "en-GB");

    // Verify unrelated labels remain unchanged.
    expect(freeLabel).to.equal("Free");
    expect(emptyLabel).to.equal("");
  });

  it("localizes marked labels within swapped content", () => {
    // Build swapped content with marked and unmarked currency labels.
    document.body.innerHTML = `
      <section id="prices">
        <span data-localized-currency>USD 5.00</span>
        <span>USD 10.00</span>
      </section>
    `;

    // Localize the marked labels within the swapped root.
    const root = document.getElementById("prices");
    localizeCurrencyElements(root);

    // Verify only marked currency labels are localized.
    expect(root.querySelector("[data-localized-currency]")?.textContent).to.equal(
      new Intl.NumberFormat(undefined, { currency: "USD", style: "currency" }).format(5),
    );
    expect(root.querySelector("span:not([data-localized-currency])")?.textContent).to.equal("USD 10.00");
  });
});

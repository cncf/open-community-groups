import { expect } from "@open-wc/testing";

import { populatePhoneCountryCodeSelect } from "/static/js/common/phone-country-code-select.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("phone country code select", () => {
  afterEach(() => {
    resetDom();
  });

  it("populates country calling codes with flags and preserves the current value", () => {
    // Prepare an account settings select with an existing value.
    document.body.innerHTML = `
      <select data-phone-country-code-select data-value="+994"></select>
    `;

    // Populate the select with country calling code options.
    const select = document.querySelector("select");
    populatePhoneCountryCodeSelect(select);

    // Verify the selector contains a broad country list and keeps the saved value.
    expect(select.value).to.equal("+994");
    expect(select.options.length).to.be.greaterThan(150);
    expect(Array.from(select.options).some((option) => option.textContent.includes("🇦🇿 Azerbaijan (+994)"))).to.equal(
      true,
    );
    expect(Array.from(select.options).some((option) => option.textContent.includes("🇺🇸 United States (+1)"))).to.equal(
      true,
    );
  });
});

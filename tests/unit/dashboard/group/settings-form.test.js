import { expect } from "@open-wc/testing";

import { initializeGroupSettings } from "/static/js/dashboard/group/settings-form.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { dispatchHtmxLoad } from "/tests/unit/test-utils/htmx.js";

describe("dashboard group settings page", () => {
  const renderSettingsForm = ({ account = "", legalName = "" } = {}) => {
    document.body.innerHTML = `
      <form id="groups-form">
        <input id="payment_recipient_seller_display_name" value="${legalName}">
        <input id="payment_recipient_recipient_id" value="${account}">
      </form>
    `;

    return {
      account: document.getElementById("payment_recipient_recipient_id"),
      legalName: document.getElementById("payment_recipient_seller_display_name"),
    };
  };

  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
  });

  it("requires both fiscal sponsor fields when either one has a value", () => {
    const fields = renderSettingsForm();
    initializeGroupSettings();

    expect(fields.legalName.required).to.equal(false);
    expect(fields.account.required).to.equal(false);

    fields.legalName.value = "Example Fiscal Sponsor, Inc.";
    fields.legalName.dispatchEvent(new Event("input", { bubbles: true }));

    expect(fields.legalName.required).to.equal(true);
    expect(fields.account.required).to.equal(true);
    expect(fields.account.validity.valueMissing).to.equal(true);

    fields.legalName.value = "";
    fields.account.value = "acct_123";
    fields.account.dispatchEvent(new Event("input", { bubbles: true }));

    expect(fields.legalName.required).to.equal(true);
    expect(fields.legalName.validity.valueMissing).to.equal(true);
    expect(fields.account.required).to.equal(true);

    fields.account.value = "";
    fields.account.dispatchEvent(new Event("input", { bubbles: true }));

    expect(fields.legalName.required).to.equal(false);
    expect(fields.account.required).to.equal(false);
  });

  it("initializes fiscal sponsor requirements in swapped settings content", () => {
    const fields = renderSettingsForm({ account: "acct_123" });

    dispatchHtmxLoad(document.body);

    expect(fields.legalName.required).to.equal(true);
    expect(fields.account.required).to.equal(true);
  });
});

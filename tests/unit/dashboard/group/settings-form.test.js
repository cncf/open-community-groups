import { expect } from "@open-wc/testing";

import { initializeGroupSettings } from "/static/js/dashboard/group/settings-form.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { dispatchHtmxLoad } from "/tests/unit/test-utils/htmx.js";

const loadSettingsTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/group/settings_update.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();

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

  it("exposes the external payments eligibility toggle", async () => {
    // Load the settings template before checking the external payments section.
    const template = normalizeWhitespace(await loadSettingsTemplate());

    expect(template).to.include('title = "External payments"');
    expect(template).to.include("{% if !external_payments.configured -%}");
    expect(template).to.include("External payments are not configured for this deployment.");
    expect(template).to.include("{% else if !external_payments.eligible -%}");
    expect(template).to.include('name="external_payments_enabled"');
    expect(template).to.include('id="external_payments_enabled"');
    expect(template).to.include('value="true"');
    expect(template).to.include("{% if group.external_payments_enabled %}checked{% endif %}");
    expect(template).to.include("{% if group.external_payments_enabled -%}");
    expect(template).to.include("This group's country is no longer on the operator allowlist.");
    expect(template).to.include("Collect paid tickets outside this platform");
    expect(template).to.include("When enabled, paid events require a payment URL instead of Stripe.");
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

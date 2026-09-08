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

    expect(template).to.include("{% if external_payments.configured -%}");
    expect(template).to.include('title = "External payments"');
    expect(template).to.include('country-code-field-name="country_code"');
    expect(template).not.to.include("External payments are not configured for this deployment.");
    expect(template).to.include("{% if !external_payments.eligible -%}");
    expect(template).to.include('name="external_payments_enabled"');
    expect(template).to.include('id="external_payments_enabled"');
    expect(template).to.include('value="true"');
    expect(template).to.include('class="sr-only peer"');
    expect(template).to.include("peer-checked:bg-primary-500");
    expect(template).to.include("peer-disabled:opacity-70");
    expect(template).to.include("{% if group.external_payments_enabled %}checked{% endif %}");
    expect(template).to.include('value="{{ group.external_payments_enabled }}"');
    expect(template).to.include("cursor-not-allowed");
    expect(template).to.include("disabled");
    expect(template).to.include("border-amber-200 bg-amber-50");
    expect(template).to.include('role="alert"');
    expect(template).to.include("External payments are not available for groups located in");
    expect(template).to.include(
      'class="font-semibold">{{ group.country_name.as_deref().unwrap_or(country_code) }}</span>',
    );
    expect(template).to.include("update the location above and save the settings.");
    expect(template).to.include("save the settings to determine eligibility.");
    expect(template).not.to.include("operator allowlist");
    expect(template).not.to.include("Eligibility is updated after the group settings are saved.");
    expect(template).to.include("Collect ticket payments outside this platform");
    expect(template).to.include("When enabled, paid events require a payment URL instead of Stripe.");
    expect(template).to.include("This option cannot be disabled while published paid events are upcoming");
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

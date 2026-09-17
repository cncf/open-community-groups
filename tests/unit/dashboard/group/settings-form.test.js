import { expect } from "@open-wc/testing";

import { createNoEmptyValuesExtension } from "/static/js/common/htmx-extensions.js";
import { initializeGroupSettings } from "/static/js/dashboard/group/settings-form.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { dispatchHtmxLoad } from "/tests/unit/test-utils/htmx.js";

const loadSettingsTemplate = async () => {
  const response = await fetch("/ocg-server/templates/dashboard/group/settings_update.html");

  expect(response.ok).to.equal(true);

  return response.text();
};

const normalizeWhitespace = (value) => value.replace(/\s+/g, " ").trim();
const formDataToEntries = (formData) => Array.from(formData.entries());

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

  it("replaces the fiscal sponsor controls with a notice when Stripe onboarding is blocked", async () => {
    // Load the settings template before checking the Fiscal Sponsor section.
    const template = normalizeWhitespace(await loadSettingsTemplate());
    const fiscalSponsorSection = template.slice(
      template.indexOf('title = "Fiscal Sponsor"'),
      template.indexOf("{# End payments section -#}"),
    );

    // The notice is rendered whenever operator policy blocks onboarding.
    expect(fiscalSponsorSection).to.include("{% if external_payments.stripe_onboarding_blocked() -%}");
    expect(fiscalSponsorSection).to.include('role="alert"');
    expect(fiscalSponsorSection).to.include("border-amber-200 bg-amber-50");
    expect(fiscalSponsorSection).to.include(
      "This deployment collects ticket payments outside the platform for groups located in",
    );
    expect(fiscalSponsorSection).to.include(
      "A Stripe connected account cannot be added or changed here; use the External payments section below.",
    );
    expect(fiscalSponsorSection).to.include("{% if group.payment_recipient.is_some() -%}");
    expect(fiscalSponsorSection).to.include(
      "The stored fiscal sponsor can still be used for paid events on Stripe",
    );
    expect(fiscalSponsorSection).to.include(
      "A removed account cannot be added again while the country stays on this list.",
    );
    expect(fiscalSponsorSection).to.include("The fiscal sponsor owns Tax Rate definitions in Stripe.");

    // Every payment recipient control shares one visibility condition.
    expect(fiscalSponsorSection).to.include("{% if self.shows_fiscal_sponsor_fields() -%}");
    const controlsStart = fiscalSponsorSection.indexOf("{% if self.shows_fiscal_sponsor_fields() -%}");
    const controls = fiscalSponsorSection.slice(controlsStart);
    expect(controls).to.include('<input type="hidden" name="payment_recipient[provider]" value="stripe">');
    expect(controls).to.include('name="payment_recipient[seller_display_name]"');
    expect(controls).to.include('id="payment_recipient_seller_display_name"');
    expect(controls).to.include('name="payment_recipient[recipient_id]"');
    expect(controls).to.include('id="payment_recipient_recipient_id"');

    // The form keeps the clearing contract regardless of rendered controls.
    expect(template).to.include(
      'data-hx-keep-empty="payment_recipient[recipient_id] payment_recipient[seller_display_name]"',
    );
  });

  it("does nothing when the fiscal sponsor controls are not rendered", () => {
    // Render the form shell without any payment recipient control.
    document.body.innerHTML = `
      <form id="groups-form">
        <input id="name" name="name" value="Group">
      </form>
    `;
    const form = document.getElementById("groups-form");

    // Initialize the settings behavior against the reduced form.
    initializeGroupSettings();

    // No field becomes required and the form is left unbound for a later render.
    expect(form.querySelector("[required]")).to.equal(null);
    expect(form.dataset.groupSettingsBound).to.equal(undefined);
  });

  it("keeps blank fiscal sponsor fields in the submitted parameters to clear the recipient", () => {
    // Build the real form shell with both sponsor fields blank and an unrelated blank field.
    document.body.innerHTML = `
      <form id="groups-form"
            hx-ext="no-empty-vals"
            data-hx-keep-empty="payment_recipient[recipient_id] payment_recipient[seller_display_name]">
        <input name="name" value="Group">
        <input name="city" value="">
        <input type="hidden" name="payment_recipient[provider]" value="stripe">
        <input id="payment_recipient_seller_display_name" name="payment_recipient[seller_display_name]" value="">
        <input id="payment_recipient_recipient_id" name="payment_recipient[recipient_id]" value="">
      </form>
    `;
    const form = document.getElementById("groups-form");
    initializeGroupSettings();

    // Serialize the form through the no-empty-vals extension used by the settings form.
    const parameters = new FormData(form);
    createNoEmptyValuesExtension(true).encodeParameters(null, parameters, form);

    // Blank sponsor fields stay submitted while the unrelated blank field is dropped.
    expect(form.checkValidity()).to.equal(true);
    expect(formDataToEntries(parameters)).to.deep.equal([
      ["name", "Group"],
      ["payment_recipient[provider]", "stripe"],
      ["payment_recipient[seller_display_name]", ""],
      ["payment_recipient[recipient_id]", ""],
    ]);
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

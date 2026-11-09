import { expect } from "@open-wc/testing";

import { createNoEmptyValuesExtension } from "/static/js/common/htmx-extensions.js";
import { initializeGroupSettings } from "/static/js/dashboard/group/settings-form.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { dispatchHtmxLoad } from "/tests/unit/test-utils/htmx.js";

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
      legalName: document.getElementById(
        "payment_recipient_seller_display_name",
      ),
    };
  };

  const renderExternalPaymentsSection = ({
    checked = false,
    legalNameDisabled = false,
    toggleDisabled = false,
  } = {}) => {
    document.body.innerHTML = `
      <form id="groups-form">
        <input type="checkbox" id="external_payments_enabled" ${checked ? "checked" : ""} ${toggleDisabled ? "disabled" : ""}>
        <input id="external_payments_seller_display_name" ${legalNameDisabled ? "disabled" : ""}>
      </form>
    `;

    return {
      legalName: document.getElementById(
        "external_payments_seller_display_name",
      ),
      toggle: document.getElementById("external_payments_enabled"),
    };
  };

  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
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
            data-hx-keep-empty="external_payments_seller_display_name payment_recipient[recipient_id] payment_recipient[seller_display_name]">
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

  it("keeps a blank external payee legal name in the submitted parameters to clear it", () => {
    // Build the external payments section with the toggle off and the legal name blank.
    document.body.innerHTML = `
      <form id="groups-form"
            hx-ext="no-empty-vals"
            data-hx-keep-empty="external_payments_seller_display_name payment_recipient[recipient_id] payment_recipient[seller_display_name]">
        <input name="name" value="Group">
        <input name="city" value="">
        <input type="hidden" name="external_payments_enabled" value="false">
        <input type="checkbox" id="external_payments_enabled" name="external_payments_enabled" value="true">
        <input id="external_payments_seller_display_name" name="external_payments_seller_display_name" value="">
      </form>
    `;
    const form = document.getElementById("groups-form");
    initializeGroupSettings();

    // Serialize the form through the no-empty-vals extension used by the settings form.
    const parameters = new FormData(form);
    createNoEmptyValuesExtension(true).encodeParameters(null, parameters, form);

    // The blank legal name stays submitted so the server clears the stored value.
    expect(form.checkValidity()).to.equal(true);
    expect(formDataToEntries(parameters)).to.deep.equal([
      ["name", "Group"],
      ["external_payments_enabled", "false"],
      ["external_payments_seller_display_name", ""],
    ]);
  });

  it("requires the external payee legal name while external payments are enabled", () => {
    const fields = renderExternalPaymentsSection();
    initializeGroupSettings();

    expect(fields.legalName.required).to.equal(false);

    fields.toggle.checked = true;
    fields.toggle.dispatchEvent(new Event("change", { bubbles: true }));

    expect(fields.legalName.required).to.equal(true);
    expect(fields.legalName.validity.valueMissing).to.equal(true);

    fields.toggle.checked = false;
    fields.toggle.dispatchEvent(new Event("change", { bubbles: true }));

    expect(fields.legalName.required).to.equal(false);
  });

  it("requires the external payee legal name when the toggle is locked on", () => {
    const fields = renderExternalPaymentsSection({
      checked: true,
      toggleDisabled: true,
    });
    initializeGroupSettings();

    expect(fields.legalName.required).to.equal(true);
  });

  it("does not require a disabled external payee legal name", () => {
    const fields = renderExternalPaymentsSection({
      legalNameDisabled: true,
      toggleDisabled: true,
    });
    initializeGroupSettings();

    expect(fields.legalName.required).to.equal(false);
  });

  it("binds the external payee requirement without fiscal sponsor controls", () => {
    const fields = renderExternalPaymentsSection({ checked: true });
    const form = document.getElementById("groups-form");

    dispatchHtmxLoad(document.body);

    expect(form.dataset.groupSettingsBound).to.equal("true");
    expect(fields.legalName.required).to.equal(true);
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

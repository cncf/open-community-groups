import { getElementById, initializeOnReadyAndHtmxLoad, markDatasetReady } from "/static/js/common/dom.js";

const SETTINGS_FORM_ID = "groups-form";
const EXTERNAL_PAYEE_LEGAL_NAME_ID = "external_payments_seller_display_name";
const EXTERNAL_PAYMENTS_ENABLED_ID = "external_payments_enabled";
const FISCAL_SPONSOR_LEGAL_NAME_ID = "payment_recipient_seller_display_name";
const FISCAL_SPONSOR_ACCOUNT_ID = "payment_recipient_recipient_id";
const SETTINGS_BOUND_KEY = "groupSettingsBound";

/**
 * Initializes group settings form behavior.
 * @param {Document|Element} root Root element to search from.
 * @returns {void}
 */
export const initializeGroupSettings = (root = document) => {
  const settingsForm = getElementById(root, SETTINGS_FORM_ID);
  const externalPayeeLegalName = getElementById(root, EXTERNAL_PAYEE_LEGAL_NAME_ID);
  const externalPaymentsToggle = getElementById(root, EXTERNAL_PAYMENTS_ENABLED_ID);
  const fiscalSponsorLegalName = getElementById(root, FISCAL_SPONSOR_LEGAL_NAME_ID);
  const fiscalSponsorAccount = getElementById(root, FISCAL_SPONSOR_ACCOUNT_ID);
  const hasExternalPayeeFields = Boolean(externalPayeeLegalName && externalPaymentsToggle);
  const hasFiscalSponsorFields = Boolean(fiscalSponsorLegalName && fiscalSponsorAccount);
  if (
    !settingsForm ||
    (!hasExternalPayeeFields && !hasFiscalSponsorFields) ||
    !markDatasetReady(settingsForm, SETTINGS_BOUND_KEY)
  ) {
    return;
  }

  if (hasExternalPayeeFields) {
    bindExternalPayeeRequirement(externalPaymentsToggle, externalPayeeLegalName);
  }
  if (hasFiscalSponsorFields) {
    bindFiscalSponsorRequirements([fiscalSponsorLegalName, fiscalSponsorAccount]);
  }
};

/**
 * Requires the external payee legal name while external payments are enabled.
 * @param {HTMLInputElement} toggle External payments checkbox.
 * @param {HTMLInputElement} legalName External payee legal name input.
 * @returns {void}
 */
const bindExternalPayeeRequirement = (toggle, legalName) => {
  const syncExternalPayeeRequirement = () => {
    legalName.required = toggle.checked && !legalName.disabled;
    legalName.setCustomValidity("");
  };

  toggle.addEventListener("change", syncExternalPayeeRequirement);
  syncExternalPayeeRequirement();
};

/**
 * Requires both fiscal sponsor fields once either one has a value.
 * @param {HTMLInputElement[]} fields Fiscal sponsor legal name and account inputs.
 * @returns {void}
 */
const bindFiscalSponsorRequirements = (fields) => {
  const syncFiscalSponsorRequirements = () => {
    const fiscalSponsorConfigured = fields.some((field) => field.value.trim());

    fields.forEach((field) => {
      field.required = fiscalSponsorConfigured;
      field.setCustomValidity("");
    });
  };

  fields.forEach((field) => {
    field.addEventListener("input", syncFiscalSponsorRequirements);
  });
  syncFiscalSponsorRequirements();
};

initializeOnReadyAndHtmxLoad(initializeGroupSettings);

import { getElementById, initializeOnReadyAndHtmxLoad, markDatasetReady } from "/static/js/common/dom.js";

const SETTINGS_FORM_ID = "groups-form";
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
  const fiscalSponsorLegalName = getElementById(root, FISCAL_SPONSOR_LEGAL_NAME_ID);
  const fiscalSponsorAccount = getElementById(root, FISCAL_SPONSOR_ACCOUNT_ID);
  if (
    !settingsForm ||
    !fiscalSponsorLegalName ||
    !fiscalSponsorAccount ||
    !markDatasetReady(settingsForm, SETTINGS_BOUND_KEY)
  ) {
    return;
  }

  const fiscalSponsorFields = [fiscalSponsorLegalName, fiscalSponsorAccount];
  const syncFiscalSponsorRequirements = () => {
    const fiscalSponsorConfigured = fiscalSponsorFields.some((field) => field.value.trim());

    fiscalSponsorFields.forEach((field) => {
      field.required = fiscalSponsorConfigured;
      field.setCustomValidity("");
    });
  };

  fiscalSponsorFields.forEach((field) => {
    field.addEventListener("input", syncFiscalSponsorRequirements);
  });
  syncFiscalSponsorRequirements();
};

initializeOnReadyAndHtmxLoad(initializeGroupSettings);

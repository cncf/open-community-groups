import { markDatasetReady, setElementHidden } from "/static/js/common/dom.js";
import { ocgFetch } from "/static/js/common/fetch.js";

const AUTOMATIC_MODE = "automatic";
const MANUAL_TAX_REQUIRED_CODE = "unsupported_country";
const RELEVANT_FIELD_NAMES = new Set([
  "kind_id",
  "tax_calculation_mode",
  "venue_address",
  "venue_city",
  "venue_country_code",
  "venue_name",
  "venue_state_code",
  "venue_zip_code",
]);
const STATE_ERROR_CODES = new Set(["state_code_required", "state_code_invalid"]);

/**
 * Initializes the saved-event automatic-tax readiness control.
 * @param {Object} config Readiness configuration.
 * @param {HTMLElement} config.pageRoot Event page root.
 * @param {(sectionName: string) => void} config.displayActiveSection Section callback.
 * @returns {void}
 */
export const initializeAutomaticTaxReadiness = ({ pageRoot, displayActiveSection }) => {
  const panel = pageRoot.querySelector("[data-automatic-tax-readiness]");
  const taxModeField = pageRoot.querySelector('[name="tax_calculation_mode"]');
  if (!panel || !taxModeField || !markDatasetReady(panel, "automaticTaxReadinessReady")) {
    return;
  }

  const checkButton = panel.querySelector('[data-automatic-tax-readiness-action="check"]');
  const manualTaxHelp = panel.querySelector('[data-automatic-tax-readiness-role="manual-tax-help"]');
  const reviewStateButton = panel.querySelector('[data-automatic-tax-readiness-action="review-state"]');
  const status = panel.querySelector('[data-automatic-tax-readiness-role="status"]');
  const saved = panel.dataset.saved === "true";
  const permanentlyDisabled = checkButton?.disabled === true;
  let stale = false;

  const syncVisibility = () => {
    setElementHidden(panel, taxModeField.value !== AUTOMATIC_MODE);
  };

  const markStale = () => {
    if (!saved || stale) {
      return;
    }

    stale = true;
    if (checkButton) {
      checkButton.disabled = true;
      checkButton.removeAttribute("aria-busy");
    }
    if (manualTaxHelp) {
      manualTaxHelp.hidden = true;
    }
    if (reviewStateButton) {
      reviewStateButton.hidden = true;
    }
    if (status) {
      status.textContent =
        "Automatic tax readiness is based on saved data. Save these changes before checking again.";
    }
  };

  const relevantFieldChanged = (event) => {
    const field = event.composedPath?.().find((element) => RELEVANT_FIELD_NAMES.has(element?.name));
    if (field || event.type === "location-selected" || event.type === "location-cleared") {
      markStale();
    }
  };

  pageRoot.addEventListener("input", relevantFieldChanged);
  pageRoot.addEventListener("change", relevantFieldChanged);
  pageRoot.addEventListener("location-selected", relevantFieldChanged);
  pageRoot.addEventListener("location-cleared", relevantFieldChanged);
  pageRoot.addEventListener("ticket-types-changed", markStale);
  taxModeField.addEventListener("change", syncVisibility);

  reviewStateButton?.addEventListener("click", async () => {
    displayActiveSection("date-venue");
    const locationField = pageRoot.querySelector("location-search-field");
    await locationField?.updateComplete;
    const stateCodeField =
      locationField?.shadowRoot?.querySelector('[name="venue_state_code"]') ||
      pageRoot.querySelector('[name="venue_state_code"]');
    stateCodeField?.focus();
  });

  checkButton?.addEventListener("click", async () => {
    if (stale || permanentlyDisabled || !panel.dataset.readinessUrl) {
      return;
    }

    checkButton.disabled = true;
    checkButton.setAttribute("aria-busy", "true");
    manualTaxHelp.hidden = true;
    reviewStateButton.hidden = true;
    status.textContent = "Checking the saved venue for automatic tax readiness…";

    try {
      const response = await ocgFetch(panel.dataset.readinessUrl, {
        credentials: "same-origin",
        headers: { Accept: "application/json" },
        method: "POST",
      });
      const result = await response.json();

      if (response.ok && result.status === "ready") {
        const stateDetail = result.state_code ? ` using state code ${result.state_code}` : "";
        const cacheDetail = result.cached ? " A matching saved provider location was reused." : "";
        status.textContent = `Automatic tax is ready for this venue${stateDetail}.${cacheDetail}`;
        return;
      }

      status.textContent =
        typeof result.message === "string" && result.message
          ? result.message
          : "Automatic tax readiness could not be confirmed. Try again later.";
      manualTaxHelp.hidden = result.code !== MANUAL_TAX_REQUIRED_CODE;
      reviewStateButton.hidden =
        !STATE_ERROR_CODES.has(result.code) || !result.fields?.includes("venue_state_code");
    } catch {
      status.textContent = "Automatic tax readiness could not be confirmed. Try again later.";
      manualTaxHelp.hidden = true;
    } finally {
      checkButton.disabled = permanentlyDisabled || stale;
      checkButton.removeAttribute("aria-busy");
    }
  });

  syncVisibility();
};

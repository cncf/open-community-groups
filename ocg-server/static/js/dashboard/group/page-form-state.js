import { queryElementById } from "/static/js/common/dom.js";

/**
 * Builds a list of existing form ids for page-level wiring.
 * @param {string[]} formIds Candidate form ids.
 * @param {Document|Element} [root=document] Query root.
 * @returns {string[]} Existing form ids only.
 */
export const collectExistingFormIds = (formIds, root = document) =>
  (formIds || []).filter((formId) => !!queryElementById(root, formId));

/**
 * Syncs a checkbox toggle with its hidden boolean input.
 * @param {object} config Toggle binding config.
 * @param {HTMLInputElement|null} config.toggle Checkbox toggle input.
 * @param {HTMLInputElement|null} config.hiddenInput Hidden input receiving "true"/"false".
 * @param {(enabled: boolean) => void} [config.onChange] Optional side effects callback.
 * @param {boolean} [config.syncOnInit=false] Whether to sync immediately.
 * @returns {{sync: () => void}} Toggle sync API.
 */
export const bindBooleanToggle = ({ toggle, hiddenInput, onChange = () => {}, syncOnInit = false }) => {
  const sync = () => {
    const enabled = toggle?.checked === true;

    if (hiddenInput) {
      hiddenInput.value = String(enabled);
    }

    onChange(enabled);
  };

  if (!toggle) {
    return { sync };
  }

  toggle.addEventListener("change", sync);

  if (syncOnInit) {
    sync();
  }

  return { sync };
};

/**
 * Wires dashboard page section buttons to matching content regions.
 * @param {object} config Tabs config.
 * @param {Document|Element} [config.root=document] Query root.
 * @param {(sectionName: string) => void} [config.onSectionChange] Section hook.
 * @returns {{displayActiveSection: (sectionName: string) => void}} Section API.
 */
export const initializeSectionTabs = ({ root = document, onSectionChange = () => {} } = {}) => {
  const displayActiveSection = (sectionName) => {
    const tabButtons = Array.from(root.querySelectorAll("[data-section]"));
    const contentSections = Array.from(root.querySelectorAll("[data-content]"));

    tabButtons.forEach((button) => {
      const isActive = button.getAttribute("data-section") === sectionName;
      button.setAttribute("data-active", isActive ? "true" : "false");
      button.classList.toggle("active", isActive);
    });

    contentSections.forEach((section) => {
      const isActive = section.getAttribute("data-content") === sectionName;
      section.classList.toggle("hidden", !isActive);
    });

    onSectionChange(sectionName);
  };

  root.addEventListener("click", (event) => {
    const button = event.target?.closest?.("[data-section]");
    if (!button || !root.contains(button)) {
      return;
    }

    displayActiveSection(button.getAttribute("data-section") || "");
  });

  return { displayActiveSection };
};

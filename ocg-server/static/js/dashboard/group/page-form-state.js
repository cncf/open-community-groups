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
  let skipSectionClickActivation = false;

  const getTabButtons = () => Array.from(root.querySelectorAll("[data-section]"));

  const getNextButtons = () => Array.from(root.querySelectorAll("[data-section-next]"));

  const updateNextButtons = (sectionName) => {
    const tabButtons = getTabButtons();
    const currentIndex = tabButtons.findIndex(
      (button) => button.getAttribute("data-section") === sectionName,
    );
    const hasNextButton = currentIndex >= 0 && currentIndex < tabButtons.length - 1;

    getNextButtons().forEach((button) => {
      button.classList.toggle("hidden", !hasNextButton);
      button.disabled = !hasNextButton;
    });
  };

  const scrollToTop = () => {
    window.scrollTo?.({
      behavior: "instant",
      left: 0,
      top: 0,
    });
  };

  const displayActiveSection = (sectionName) => {
    const tabButtons = getTabButtons();
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

    updateNextButtons(sectionName);
    onSectionChange(sectionName);
  };

  root.addEventListener("click", (event) => {
    const nextButton = event.target?.closest?.("[data-section-next]");
    if (nextButton && root.contains(nextButton)) {
      event.preventDefault();
      event.stopPropagation();

      const tabButtons = getTabButtons();
      const currentIndex = tabButtons.findIndex((button) => button.getAttribute("data-active") === "true");
      const nextTabButton = tabButtons[currentIndex + 1];
      const nextSectionName = nextTabButton?.getAttribute("data-section") || "";

      if (!nextTabButton || !nextSectionName) {
        updateNextButtons(tabButtons[currentIndex]?.getAttribute("data-section") || "");
        return;
      }

      skipSectionClickActivation = true;
      try {
        nextTabButton.click();
      } finally {
        skipSectionClickActivation = false;
      }

      displayActiveSection(nextSectionName);
      scrollToTop();
      return;
    }

    const button = event.target?.closest?.("[data-section]");
    if (!button || !root.contains(button)) {
      return;
    }

    if (skipSectionClickActivation) {
      return;
    }

    displayActiveSection(button.getAttribute("data-section") || "");
  });

  const activeSectionName =
    getTabButtons()
      .find((button) => button.getAttribute("data-active") === "true")
      ?.getAttribute("data-section") || "";
  updateNextButtons(activeSectionName);

  return { displayActiveSection };
};

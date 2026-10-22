/** Selector of the options hidden until their list is expanded. */
const HIDDEN_OPTION_SELECTOR = "[data-question-option-hidden]";

/** Selector of the text element of an options toggle. */
const OPTIONS_LABEL_SELECTOR = "[data-question-options-label]";

/** Selector of the buttons that expand or collapse an options list. */
const OPTIONS_TOGGLE_SELECTOR = "[data-question-options-toggle]";

/**
 * Roots whose delegated toggles are bound. Kept in memory, unlike a dataset
 * marker, so roots restored from the HTMX history cache bind again.
 */
const boundRoots = new WeakSet();

/**
 * Binds the delegated "Show N more" options toggles of a root once.
 * @param {Document|Element} root - Root containing question breakdowns.
 * @returns {void}
 */
export const bindQuestionOptionsToggles = (root) => {
  if (!root || boundRoots.has(root)) {
    return;
  }
  boundRoots.add(root);

  root.addEventListener("click", (event) => {
    const target = event.target instanceof Element ? event.target : null;
    const toggle = target?.closest(OPTIONS_TOGGLE_SELECTOR);
    if (toggle && (root === toggle.ownerDocument || root.contains(toggle))) {
      toggleQuestionOptions(toggle);
    }
  });
};

/**
 * Shows or hides the options of a "Show N more" list beyond the visible ones,
 * keeping the toggle label and expanded state in sync. Labels come from the
 * toggle `data-label-collapsed` and `data-label-expanded` attributes and stay
 * unchanged when those attributes are missing.
 * @param {HTMLButtonElement} button - Options toggle button.
 * @returns {void}
 */
export const toggleQuestionOptions = (button) => {
  const listId = button.getAttribute("aria-controls") || "";
  const list = listId ? button.ownerDocument.getElementById(listId) : null;
  if (!list) {
    return;
  }

  const expanded = button.getAttribute("aria-expanded") !== "true";
  list.querySelectorAll(HIDDEN_OPTION_SELECTOR).forEach((option) => {
    option.hidden = !expanded;
  });
  button.setAttribute("aria-expanded", String(expanded));

  const labelText = expanded ? button.dataset.labelExpanded : button.dataset.labelCollapsed;
  if (labelText) {
    const label = button.querySelector(OPTIONS_LABEL_SELECTOR) || button;
    label.textContent = labelText;
  }
};

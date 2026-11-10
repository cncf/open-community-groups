const FILTER_COMPONENT_SELECTOR = "collapsible-filter, multi-select-filter";
const FOCUSABLE_CONTROL_SELECTOR = "input, button, select";

/**
 * Captures the filter control that has focus inside an Explore filters form,
 * so the same control can take focus again once a section swap replaces it.
 * @param {HTMLFormElement} form - Filters form about to be replaced
 * @returns {{filterName: string|null, formId: string, key: string|null}|null}
 *   Snapshot, or null when focus is outside the form
 */
export const captureFilterFocus = (form) => {
  const active = document.activeElement;
  if (!form?.id || !(active instanceof Element) || !form.contains(active)) {
    return null;
  }

  return {
    filterName: active.closest(FILTER_COMPONENT_SELECTOR)?.getAttribute("name") ?? null,
    formId: form.id,
    key: getFilterFocusKey(active),
  };
};

/**
 * Builds a key that identifies a filter control across re-renders.
 * @param {Element|null} element - Filter control
 * @returns {string|null} Explicit data-focus-key, name=value for checkboxes and
 *   radios, name for other named inputs, or null
 */
export const getFilterFocusKey = (element) => {
  if (!(element instanceof HTMLElement)) {
    return null;
  }

  if (element.dataset.focusKey) {
    return element.dataset.focusKey;
  }

  const name = element.getAttribute("name");
  if (!name) {
    return null;
  }

  if (element instanceof HTMLInputElement && (element.type === "checkbox" || element.type === "radio")) {
    return `${name}=${element.value}`;
  }
  return name;
};

/**
 * Moves focus back to the captured filter control after a section swap. Lit
 * filters render after the swap, so it waits for them first. Filters that can
 * restore focus themselves do it, so dropdowns stay closed. Focus that
 * already left the body, for example through htmx's own id restore, stays.
 * @param {{filterName: string|null, formId: string, key: string|null}|null} snapshot
 *   Snapshot from captureFilterFocus
 * @returns {Promise<void>} Resolves once focus is placed or left alone
 */
export const restoreFilterFocus = async (snapshot) => {
  if (!snapshot || !isFocusOnBody()) {
    return;
  }

  const form = document.getElementById(snapshot.formId);
  if (!form) {
    return;
  }

  // Wait for the filter components of the new form to render their controls.
  await Promise.all(
    [...form.querySelectorAll(FILTER_COMPONENT_SELECTOR)].map((filter) => filter.updateComplete),
  );
  if (!isFocusOnBody()) {
    return;
  }

  // Look inside the same filter component when there was one, else in the whole form.
  const scope = snapshot.filterName ? findFilter(form, snapshot.filterName) : form;
  if (!scope) {
    return;
  }

  const controls = [...scope.querySelectorAll(FOCUSABLE_CONTROL_SELECTOR)].filter(isFocusableControl);
  const target =
    (snapshot.key && controls.find((control) => getFilterFocusKey(control) === snapshot.key)) ||
    (snapshot.filterName ? controls[0] : null);
  if (!target) {
    return;
  }
  const filter = target.closest(FILTER_COMPONENT_SELECTOR);
  if (typeof filter?.restoreFocus === "function") {
    filter.restoreFocus(target);
  } else {
    target.focus({ preventScroll: true });
  }
};

/**
 * Finds a filter component by name inside a form.
 * @param {HTMLFormElement} form - Filters form
 * @param {string} name - Filter name attribute
 * @returns {Element|undefined} Filter component
 */
const findFilter = (form, name) =>
  [...form.querySelectorAll(FILTER_COMPONENT_SELECTOR)].find(
    (filter) => filter.getAttribute("name") === name,
  );

/**
 * Checks whether no element holds focus.
 * @returns {boolean} True when focus sits on the body
 */
const isFocusOnBody = () => !document.activeElement || document.activeElement === document.body;

/**
 * Checks whether a control can take focus: enabled, not a hidden input, and rendered.
 * @param {HTMLInputElement|HTMLButtonElement|HTMLSelectElement} control - Candidate control
 * @returns {boolean} True when the control can take focus
 */
const isFocusableControl = (control) =>
  !control.disabled && control.type !== "hidden" && control.checkVisibility();

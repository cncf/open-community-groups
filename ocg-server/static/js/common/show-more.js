// Show more buttons that replace their own list item with the next items.
const SHOW_MORE_SELECTOR = "[data-show-more]";
// Focusable controls preferred over the appended item itself.
const FOCUSABLE_SELECTOR =
  "a[href], button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex='-1'])";

// Roots whose show more swaps are handled.
const boundRoots = new WeakSet();

/**
 * Keeps keyboard focus on the list when a show more button replaces its list
 * item with the next items, moving it to the first appended item.
 * @param {Document|Element} root Element containing show more buttons.
 * @returns {void}
 */
export const bindShowMoreFocus = (root) => {
  if (!root?.addEventListener || boundRoots.has(root)) {
    return;
  }
  boundRoots.add(root);

  let pending = null;

  // Remember where the next items start before the button item is replaced
  root.addEventListener("htmx:beforeSwap", (event) => {
    const button = event.detail?.requestConfig?.elt ?? event.detail?.elt;
    const item = event.detail?.target;
    if (!(button instanceof Element) || !button.matches(SHOW_MORE_SELECTOR) || !(item instanceof Element)) {
      return;
    }
    if (!event.detail?.shouldSwap || !item.contains(button) || !item.parentElement) {
      return;
    }
    pending = {
      hadFocus: item.contains(document.activeElement) || document.activeElement === document.body,
      list: item.parentElement,
      previous: item.previousElementSibling,
    };
  });

  // Focus the first appended item once the swap settles
  root.addEventListener("htmx:afterSettle", () => {
    if (!pending) {
      return;
    }
    const { hadFocus, list, previous } = pending;
    pending = null;
    if (hadFocus) {
      focusFirstAppendedItem(list, previous);
    }
  });
};

/**
 * Focuses the item following the last item shown before the swap, preferring
 * its first control.
 * @param {Element} list List the items were appended to.
 * @param {Element|null} previous Last item shown before the swap.
 * @returns {void}
 */
const focusFirstAppendedItem = (list, previous) => {
  const item = previous?.isConnected ? previous.nextElementSibling : list.firstElementChild;
  if (!(item instanceof HTMLElement)) {
    return;
  }

  const control = item.querySelector(FOCUSABLE_SELECTOR);
  if (control instanceof HTMLElement) {
    control.focus();
    return;
  }
  if (!item.hasAttribute("tabindex")) {
    item.setAttribute("tabindex", "-1");
  }
  item.focus();
};

import { closestElement, markDatasetReady } from "/static/js/common/dom.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";

const ACTIONS_MENU_SELECTOR = "[data-actions-menu]";
const ACTIONS_MENU_DROPDOWN_SELECTOR = ":scope > .dropdown";
const DATA_KEY = "actionsMenuReady";
const VIEWPORT_GAP = 8;
const CLIPPING_OVERFLOW_VALUES = new Set(["auto", "clip", "hidden", "scroll"]);

/**
 * Finds the visible vertical bounds imposed by the viewport and ancestors.
 * @param {HTMLElement} menu Action menu trigger wrapper.
 * @returns {{top: number, bottom: number}} Visible vertical bounds.
 */
const getVisibleVerticalBounds = (menu) => {
  const bounds = {
    top: VIEWPORT_GAP,
    bottom: window.innerHeight - VIEWPORT_GAP,
  };
  let ancestor = menu.parentElement;

  while (ancestor) {
    const styles = window.getComputedStyle(ancestor);
    if (CLIPPING_OVERFLOW_VALUES.has(styles.overflowY) || CLIPPING_OVERFLOW_VALUES.has(styles.overflow)) {
      const ancestorBounds = ancestor.getBoundingClientRect();
      bounds.top = Math.max(bounds.top, ancestorBounds.top + VIEWPORT_GAP);
      bounds.bottom = Math.min(bounds.bottom, ancestorBounds.bottom - VIEWPORT_GAP);
    }
    ancestor = ancestor.parentElement;
  }

  return bounds;
};

/**
 * Opens an action menu above its trigger when it would cross the viewport edge.
 * @param {HTMLDetailsElement} menu Open action menu.
 * @returns {void}
 */
export const positionActionsMenu = (menu) => {
  if (!(menu instanceof HTMLDetailsElement)) {
    return;
  }

  const dropdown = menu.querySelector(ACTIONS_MENU_DROPDOWN_SELECTOR);
  if (!(dropdown instanceof HTMLElement)) {
    return;
  }

  dropdown.style.insetBlockStart = "";
  dropdown.style.insetBlockEnd = "";
  if (!menu.open) {
    return;
  }

  const menuBounds = menu.getBoundingClientRect();
  const dropdownBounds = dropdown.getBoundingClientRect();
  const visibleBounds = getVisibleVerticalBounds(menu);
  const availableAbove = menuBounds.top - visibleBounds.top;
  const availableBelow = visibleBounds.bottom - menuBounds.bottom;
  if (dropdownBounds.bottom > visibleBounds.bottom && availableAbove > availableBelow) {
    dropdown.style.insetBlockStart = "auto";
    dropdown.style.insetBlockEnd = `calc(100% + ${VIEWPORT_GAP}px)`;
  }
};

/**
 * Closes details-based action menus within a root.
 * @param {Document|Element} [root=document] Query root.
 * @param {HTMLDetailsElement|null} [exceptMenu=null] Menu to keep open.
 * @returns {void}
 */
export const closeActionsMenus = (root = document, exceptMenu = null) => {
  root.querySelectorAll?.(`${ACTIONS_MENU_SELECTOR}[open]`).forEach((menu) => {
    if (menu instanceof HTMLDetailsElement && menu !== exceptMenu) {
      menu.open = false;
    }
  });
};

/**
 * Initializes delegated details-based action menu behavior.
 * @returns {void}
 */
export const initializeActionsMenus = () => {
  if (!markDatasetReady(document.documentElement, DATA_KEY)) {
    return;
  }

  document.addEventListener("click", (event) => {
    const summary = closestElement(event.target, `${ACTIONS_MENU_SELECTOR} > summary`);
    const menu = summary?.closest(ACTIONS_MENU_SELECTOR);
    if (menu instanceof HTMLDetailsElement) {
      closeActionsMenus(document, menu);
      return;
    }

    const menuItem = closestElement(
      event.target,
      `${ACTIONS_MENU_SELECTOR} a, ${ACTIONS_MENU_SELECTOR} button`,
    );
    if (menuItem) {
      closeActionsMenus();
      return;
    }

    if (!closestElement(event.target, ACTIONS_MENU_SELECTOR)) {
      closeActionsMenus();
    }
  });

  document.addEventListener("keydown", (event) => {
    if (!isEscapeEvent(event)) {
      return;
    }

    const focusedMenu = closestElement(document.activeElement, ACTIONS_MENU_SELECTOR);
    const openMenu =
      focusedMenu instanceof HTMLDetailsElement && focusedMenu.open
        ? focusedMenu
        : document.querySelector(`${ACTIONS_MENU_SELECTOR}[open]`);
    if (!(openMenu instanceof HTMLDetailsElement)) {
      return;
    }

    const summary = openMenu.querySelector("summary");
    closeActionsMenus();
    if (summary instanceof HTMLElement) {
      event.preventDefault();
      summary.focus();
    }
  });

  document.addEventListener(
    "toggle",
    (event) => {
      const menu = event.target;
      if (menu instanceof HTMLDetailsElement && menu.matches(ACTIONS_MENU_SELECTOR)) {
        positionActionsMenu(menu);
      }
    },
    true,
  );
};

initializeActionsMenus();

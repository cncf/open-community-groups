import { closestElement, markDatasetReady } from "/static/js/common/dom.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";

const ACTIONS_MENU_SELECTOR = "[data-actions-menu]";
const DATA_KEY = "actionsMenuReady";

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
};

initializeActionsMenus();

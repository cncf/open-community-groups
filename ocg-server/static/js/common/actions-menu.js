import { closestElement, markDatasetReady } from "/static/js/common/dom.js";
import { getVisibleVerticalBounds } from "/static/js/common/dropdown-placement.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";

const ACTIONS_MENU_SELECTOR = "[data-actions-menu]";
const ACTIONS_MENU_DROPDOWN_SELECTOR = ":scope > .dropdown";
const DATA_KEY = "actionsMenuReady";
const VIEWPORT_GAP = 8;

/**
 * Clears inline placement so a dropdown uses its template position.
 * @param {HTMLElement} dropdown Action menu dropdown.
 * @returns {void}
 */
const clearDropdownPlacement = (dropdown) => {
  dropdown.style.insetBlockStart = "";
  dropdown.style.insetBlockEnd = "";
};

/**
 * Opens a visible dropdown above its anchor when it would cross the visible edge.
 * @param {HTMLElement} anchor Positioned element the dropdown is placed against.
 * @param {HTMLElement} dropdown Visible dropdown element.
 * @returns {void}
 */
export const positionActionsDropdown = (anchor, dropdown) => {
  if (!(anchor instanceof HTMLElement) || !(dropdown instanceof HTMLElement)) {
    return;
  }

  // Measure the template position before choosing a direction
  clearDropdownPlacement(dropdown);
  const anchorBounds = anchor.getBoundingClientRect();
  const dropdownBounds = dropdown.getBoundingClientRect();
  const visibleBounds = getVisibleVerticalBounds(anchor, VIEWPORT_GAP);
  const availableAbove = anchorBounds.top - visibleBounds.top;
  const availableBelow = visibleBounds.bottom - anchorBounds.bottom;

  // Open upward only when that side has more room
  if (dropdownBounds.bottom > visibleBounds.bottom && availableAbove > availableBelow) {
    dropdown.style.insetBlockStart = "auto";
    dropdown.style.insetBlockEnd = `calc(100% + ${VIEWPORT_GAP}px)`;
  }
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

  if (!menu.open) {
    clearDropdownPlacement(dropdown);
    return;
  }

  positionActionsDropdown(menu, dropdown);
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

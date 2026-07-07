import {
  closestElementWithinRoot,
  getElementById,
  isElementHidden,
  markDatasetReady,
  setElementHidden,
} from "/static/js/common/dom.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import { attendeesRootSelector } from "/static/js/dashboard/group/attendees/shared.js";

const attendeeActionsDropdownId = "attendee-actions-menu";
const attendeeEmailActionsDropdownId = "attendee-email-actions-menu";
const attendeeActionsDropdownSelector = "[data-attendee-actions-dropdown]";
const attendeeEmailActionsDropdownSelector = "[data-attendee-email-actions-dropdown]";
const attendeeRowActionsMenuSelector = "[data-attendee-row-actions-menu]";

/**
 * Close the attendee actions dropdown.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
export const closeAttendeeActionsDropdown = (root = document) => {
  setElementHidden(getElementById(root, attendeeActionsDropdownId), true);
};

/**
 * Close the attendee email actions dropdown.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
export const closeAttendeeEmailActionsDropdown = (root = document) => {
  setElementHidden(getElementById(root, attendeeEmailActionsDropdownId), true);
};

/**
 * Close attendee row action menus.
 * @param {Document|Element} [root=document] Query root.
 * @param {HTMLDetailsElement|null} [exceptMenu=null] Menu to keep open.
 * @returns {void}
 */
export const closeAttendeeRowActionMenus = (root = document, exceptMenu = null) => {
  root.querySelectorAll?.(`${attendeeRowActionsMenuSelector}[open]`).forEach((menu) => {
    if (menu instanceof HTMLDetailsElement && menu !== exceptMenu) {
      menu.open = false;
    }
  });
};

/**
 * Toggle the attendee actions dropdown.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const toggleAttendeeActionsDropdown = (root = document) => {
  const dropdown = getElementById(root, attendeeActionsDropdownId);
  setElementHidden(dropdown, !isElementHidden(dropdown));
};

/**
 * Toggle the attendee email actions dropdown.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const toggleAttendeeEmailActionsDropdown = (root = document) => {
  const dropdown = getElementById(root, attendeeEmailActionsDropdownId);
  setElementHidden(dropdown, !isElementHidden(dropdown));
};

/**
 * Initialize the attendee actions dropdown.
 * @param {Document|Element} [root=document] Query root.
 */
export const initializeAttendeeActionsMenu = (root = document) => {
  if (!(root instanceof Element) || !markDatasetReady(root, "attendeeActionsMenuReady")) {
    return;
  }

  root.addEventListener("click", (event) => {
    const rowSummary = closestElementWithinRoot(
      event.target,
      `${attendeeRowActionsMenuSelector} summary`,
      root,
    );
    const rowMenu = rowSummary?.closest(attendeeRowActionsMenuSelector);
    if (rowMenu instanceof HTMLDetailsElement) {
      closeAttendeeActionsDropdown(root);
      closeAttendeeEmailActionsDropdown(root);
      closeAttendeeRowActionMenus(root, rowMenu);
      return;
    }

    const rowMenuItem = closestElementWithinRoot(
      event.target,
      `${attendeeRowActionsMenuSelector} button, ${attendeeRowActionsMenuSelector} a`,
      root,
    );
    if (rowMenuItem instanceof HTMLElement) {
      closeAttendeeRowActionMenus(root);
      return;
    }

    const trigger = closestElementWithinRoot(event.target, "#attendee-actions-button", root);
    if (trigger instanceof HTMLElement) {
      event.stopPropagation();
      closeAttendeeEmailActionsDropdown(root);
      closeAttendeeRowActionMenus(root);
      toggleAttendeeActionsDropdown(root);
      return;
    }

    const emailTrigger = closestElementWithinRoot(event.target, "#attendee-email-actions-button", root);
    if (emailTrigger instanceof HTMLButtonElement && !emailTrigger.disabled) {
      event.stopPropagation();
      closeAttendeeActionsDropdown(root);
      closeAttendeeRowActionMenus(root);
      toggleAttendeeEmailActionsDropdown(root);
      return;
    }

    const menuItem = closestElementWithinRoot(
      event.target,
      `${attendeeActionsDropdownSelector} a, ${attendeeActionsDropdownSelector} button`,
      root,
    );
    if (menuItem instanceof HTMLElement) {
      closeAttendeeActionsDropdown(root);
      return;
    }

    const emailMenuItem = closestElementWithinRoot(
      event.target,
      `${attendeeEmailActionsDropdownSelector} button`,
      root,
    );
    if (emailMenuItem instanceof HTMLButtonElement) {
      closeAttendeeEmailActionsDropdown(root);
      return;
    }

    if (!closestElementWithinRoot(event.target, attendeeActionsDropdownSelector, root)) {
      closeAttendeeActionsDropdown(root);
    }

    if (!closestElementWithinRoot(event.target, attendeeEmailActionsDropdownSelector, root)) {
      closeAttendeeEmailActionsDropdown(root);
    }

    if (!closestElementWithinRoot(event.target, attendeeRowActionsMenuSelector, root)) {
      closeAttendeeRowActionMenus(root);
    }
  });

  root.addEventListener("keydown", (event) => {
    if (isEscapeEvent(event)) {
      const openRowMenu = root.querySelector(`${attendeeRowActionsMenuSelector}[open]`);
      const rowSummary = openRowMenu?.querySelector("summary");
      closeAttendeeActionsDropdown(root);
      closeAttendeeEmailActionsDropdown(root);
      closeAttendeeRowActionMenus(root);
      if (rowSummary instanceof HTMLElement) {
        rowSummary.focus();
        return;
      }
      getElementById(root, "attendee-actions-button")?.focus();
    }
  });
};

/**
 * Initialize document-level attendee menu cleanup.
 */
export const initializeAttendeeOutsideClickListener = () => {
  if (!markDatasetReady(document.documentElement, "attendeeOutsideClickReady")) {
    return;
  }

  document.addEventListener("click", (event) => {
    const target = event.target instanceof Element ? event.target : null;
    if (!target) {
      return;
    }

    document.querySelectorAll(attendeesRootSelector).forEach((root) => {
      if (!root.contains(target)) {
        closeAttendeeActionsDropdown(root);
        closeAttendeeEmailActionsDropdown(root);
        closeAttendeeRowActionMenus(root);
      }
    });
  });
};

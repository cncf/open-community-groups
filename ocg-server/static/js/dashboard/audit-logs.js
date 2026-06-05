import { toggleModalVisibility } from "/static/js/common/common.js";
import {
  getElementById,
  initializeOnReadyAndHtmxLoad,
  markDatasetReady,
} from "/static/js/common/dom.js";

const MODAL_ID = "audit-log-filters-modal";
const OPEN_BUTTON_ID = "open-audit-log-filters-modal";
const ACTIVE_INDICATOR_ID = "audit-log-filters-active-indicator";
const CLOSE_BUTTON_ID = "close-audit-log-filters-modal";
const OVERLAY_ID = "overlay-audit-log-filters-modal";
const FORM_ID = "audit-log-filters-form";
const RESET_BUTTON_ID = "reset-audit-log-filters";
const ACTION_FILTER_ID = "audit-action";
const ACTOR_FILTER_ID = "audit-actor";
const DATE_FROM_FILTER_ID = "audit-date-from";
const DATE_TO_FILTER_ID = "audit-date-to";
const DETAILS_GROUP_SELECTOR = "[data-audit-log-details-group]";
const DETAILS_TRIGGER_SELECTOR = "[data-audit-log-details-trigger]";
const DETAILS_HOVER_DISABLED_ATTRIBUTE = "data-audit-log-hover-disabled";
const DETAILS_HOVER_BOUND_ATTRIBUTE = "data-audit-log-hover-bound";

let auditLogGlobalHandlersBound = false;

/**
 * Returns the popover card controlled by the provided trigger.
 * @param {Element} trigger - Details popover trigger button.
 * @returns {HTMLElement|null} Matching popover card element.
 */
const getAuditLogDetailsCard = (trigger) => {
  const popoverId = trigger.getAttribute("aria-controls");
  return popoverId ? getElementById(document, popoverId) : null;
};

/**
 * Returns the popover group that contains the provided trigger.
 * @param {Element} trigger - Details popover trigger button.
 * @returns {HTMLElement|null} Matching popover group element.
 */
const getAuditLogDetailsGroup = (trigger) => {
  const group = trigger.closest(DETAILS_GROUP_SELECTOR);
  return group instanceof HTMLElement ? group : null;
};

/**
 * Enables or disables hover-driven popover visibility for the trigger group.
 * @param {Element} trigger - Details popover trigger button.
 * @param {boolean} disabled - Whether hover behavior should be disabled.
 * @returns {void}
 */
const setAuditLogDetailsHoverDisabled = (trigger, disabled) => {
  const group = getAuditLogDetailsGroup(trigger);

  if (!group) {
    return;
  }

  if (disabled) {
    group.setAttribute(DETAILS_HOVER_DISABLED_ATTRIBUTE, "true");
    return;
  }

  group.removeAttribute(DETAILS_HOVER_DISABLED_ATTRIBUTE);
};

/**
 * Syncs the details trigger state with its associated popover visibility.
 * @param {Element} trigger - Details popover trigger button.
 * @param {boolean} expanded - Whether the popover should be shown.
 * @returns {void}
 */
const setAuditLogDetailsExpanded = (trigger, expanded) => {
  const card = getAuditLogDetailsCard(trigger);

  trigger.setAttribute("aria-expanded", String(expanded));
  card?.classList.toggle("hidden", !expanded);
};

/**
 * Closes all audit log detail popovers except the optional open trigger.
 * @param {Document|Element} root - Root element to search from.
 * @param {Element|null} triggerToKeepOpen - Trigger that should remain open.
 * @returns {void}
 */
const closeAuditLogDetails = (root = document, triggerToKeepOpen = null) => {
  root.querySelectorAll(DETAILS_TRIGGER_SELECTOR).forEach((trigger) => {
    setAuditLogDetailsHoverDisabled(trigger, false);
    setAuditLogDetailsExpanded(trigger, trigger === triggerToKeepOpen);
  });
};

/**
 * Resets all audit log detail popovers after an HTMX content swap.
 * @param {Document|Element} root - Root element to search from.
 * @returns {void}
 */
const syncAuditLogDetails = (root = document) => {
  closeAuditLogDetails(root);

  root.querySelectorAll(DETAILS_GROUP_SELECTOR).forEach((group) => {
    if (group.getAttribute(DETAILS_HOVER_BOUND_ATTRIBUTE) === "true") {
      return;
    }

    group.setAttribute(DETAILS_HOVER_BOUND_ATTRIBUTE, "true");
    group.addEventListener("mouseenter", () => {
      const currentTrigger = group.querySelector(DETAILS_TRIGGER_SELECTOR);

      document.querySelectorAll(DETAILS_TRIGGER_SELECTOR).forEach((trigger) => {
        if (trigger !== currentTrigger) {
          setAuditLogDetailsExpanded(trigger, false);
        }
      });
    });
    group.addEventListener("mouseleave", () => {
      group.removeAttribute(DETAILS_HOVER_DISABLED_ATTRIBUTE);
    });
  });
};

/**
 * Closes the audit log filters modal when it is currently open.
 * @returns {void}
 */
const closeAuditLogFiltersModal = () => {
  const currentModal = getElementById(document, MODAL_ID);
  if (currentModal && !currentModal.classList.contains("hidden")) {
    toggleModalVisibility(MODAL_ID);
  }
};

const bindAuditLogGlobalHandlers = () => {
  if (auditLogGlobalHandlersBound) {
    return;
  }

  auditLogGlobalHandlersBound = true;

  document.addEventListener("click", (event) => {
    if (!(event.target instanceof Element)) {
      return;
    }

    const trigger = event.target.closest(DETAILS_TRIGGER_SELECTOR);

    if (trigger) {
      const isExpanded = trigger.getAttribute("aria-expanded") === "true";

      closeAuditLogDetails(document, isExpanded ? null : trigger);
      setAuditLogDetailsHoverDisabled(trigger, isExpanded);
      return;
    }

    if (!event.target.closest(DETAILS_GROUP_SELECTOR)) {
      closeAuditLogDetails(document);
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") {
      return;
    }

    closeAuditLogFiltersModal();
    closeAuditLogDetails(document);
  });
};

/**
 * Initializes the audit log filters modal for the current content root.
 * @param {Document|Element} root - Root element to search from.
 * @returns {void}
 */
const initializeAuditLogFilters = (root = document) => {
  const modal = getElementById(root, MODAL_ID);

  if (!markDatasetReady(modal, "bound")) {
    return;
  }

  const openButton = getElementById(root, OPEN_BUTTON_ID);
  const activeIndicator = getElementById(root, ACTIVE_INDICATOR_ID);
  const closeButton = getElementById(root, CLOSE_BUTTON_ID);
  const overlay = getElementById(root, OVERLAY_ID);
  const form = getElementById(root, FORM_ID);
  const resetButton = getElementById(root, RESET_BUTTON_ID);
  const actionFilter = getElementById(root, ACTION_FILTER_ID);
  const actorFilter = getElementById(root, ACTOR_FILTER_ID);
  const dateFromFilter = getElementById(root, DATE_FROM_FILTER_ID);
  const dateToFilter = getElementById(root, DATE_TO_FILTER_ID);
  const filterFields = [actionFilter, actorFilter, dateFromFilter, dateToFilter];
  const hasActiveFilters = () => filterFields.some((field) => field?.value.trim());
  const syncActiveFiltersIndicator = () => {
    const active = hasActiveFilters();

    activeIndicator?.classList.toggle("hidden", !active);
    openButton?.setAttribute("aria-pressed", String(active));
  };
  const closeModal = () => closeAuditLogFiltersModal();

  openButton?.addEventListener("click", () => toggleModalVisibility(MODAL_ID));
  closeButton?.addEventListener("click", closeModal);
  overlay?.addEventListener("click", closeModal);
  form?.addEventListener("submit", closeModal);
  resetButton?.addEventListener("click", closeModal);
  syncActiveFiltersIndicator();
};

/**
 * Initializes audit log page behavior for the current content root.
 * @param {Document|Element} root - Root element to search from.
 * @returns {void}
 */
export const initializeAuditLogs = (root = document) => {
  bindAuditLogGlobalHandlers();
  initializeAuditLogFilters(root);
  syncAuditLogDetails(root);
};

initializeOnReadyAndHtmxLoad(() => initializeAuditLogs(document));

import { confirmAction, confirmSeriesAction, handleHtmxResponse } from "/static/js/common/alerts.js";
import {
  closestElement,
  closestElementWithinRoot,
  getElementById,
  initializeMatchingRoots,
  initializeOnReadyAndHtmxLoad,
  isElementHidden,
  setElementHidden,
} from "/static/js/common/dom.js";
import { parseJsonText } from "/static/js/common/utils.js";
import { initializeAnswersModal } from "/static/js/dashboard/group/attendees/answers.js";

const EVENT_ACTION_DROPDOWN_SELECTOR = "[data-event-actions-dropdown]";
const EVENT_ACTIONS_BUTTON_SELECTOR = ".btn-actions";
const EVENTS_LIST_PAGE_SELECTOR = "[data-events-list-page]";
const INVITATION_REQUEST_ANSWERS_MODAL = {
  closeSelector:
    "#close-invitation-request-answers-modal, #cancel-invitation-request-answers-modal, #overlay-invitation-request-answers-modal",
  contentId: "invitation-request-answers-content",
  modalId: "invitation-request-answers-modal",
  nameId: "invitation-request-answers-name",
};
// Row-level ticket allocation forms share feedback and ticket select behavior.
const ROW_TICKET_ACTION_SELECTOR = "[data-invitation-request-action], [data-waitlist-invite-action]";
// Maps capacity conflicts from ticket allocation to organizer guidance.
const ROW_TICKET_CONFLICT_MESSAGES = {
  "queue-has-priority":
    "The remaining seats for this ticket type were offered to people on the waiting list. Add seats to allocate another ticket.",
  "ticket-type-sold-out":
    "This ticket type is sold out. Add seats or cancel a pending offer before allocating another ticket.",
};
const ROW_TICKET_CONFLICT_REFRESH_EVENTS = [
  "refresh-event-attendees",
  "refresh-event-invitation-requests",
  "refresh-event-waitlist",
];
const ROW_TICKET_EMPTY_SELECTOR =
  "[data-invitation-request-ticket-empty], [data-waitlist-invite-ticket-empty]";
const ROW_TICKET_SUBMIT_SELECTOR =
  "[data-invitation-request-ticket-submit], [data-waitlist-invite-ticket-submit]";
const ROW_TICKET_TYPE_SELECTOR = "[data-invitation-request-ticket-type], [data-waitlist-invite-ticket-type]";
const TABLE_FILTER_MENU_SELECTOR = "[data-table-filter-menu]";
const initializedRoots = new WeakSet();
let documentDismissHandlerBound = false;

/**
 * Initializes scoped events-list actions and invitation request feedback.
 * @param {Document|Element} root Root element containing the events list page.
 * @returns {void}
 */
export const initializeEventsListPage = (root = document) => {
  if (!root || initializedRoots.has(root)) {
    return;
  }

  initializedRoots.add(root);
  bindDocumentDropdownDismissHandler();

  // Bind request-answer review only when this page owns the modal
  if (getElementById(root, INVITATION_REQUEST_ANSWERS_MODAL.modalId)) {
    initializeAnswersModal(root, INVITATION_REQUEST_ANSWERS_MODAL, prepareInvitationRequestAnswersOpen);
  }
  initializeRowTicketControls(root);

  root.addEventListener("click", (event) => {
    const actionsButton = closestElementWithinRoot(event.target, EVENT_ACTIONS_BUTTON_SELECTOR, root);
    if (actionsButton) {
      event.preventDefault();
      handleActionsMenuClick(actionsButton, root);
      return;
    }

    const scopedActionButton = closestElementWithinRoot(event.target, "[data-event-scoped-action]", root);
    if (scopedActionButton) {
      handleScopedActionClick(scopedActionButton);
      return;
    }

    if (!closestElementWithinRoot(event.target, EVENT_ACTION_DROPDOWN_SELECTOR, root)) {
      closeDropdowns(root, null, true);
    }
  });

  root.addEventListener("htmx:afterRequest", (event) => {
    const scopedActionButton = closestElementWithinRoot(event.target, "[data-event-scoped-action]", root);
    if (scopedActionButton) {
      handleScopedActionAfterRequest(scopedActionButton, event);
      return;
    }

    const rowTicketAction = closestElementWithinRoot(event.target, ROW_TICKET_ACTION_SELECTOR, root);
    if (rowTicketAction) {
      handleRowTicketActionAfterRequest(rowTicketAction, event);
    }
  });

  root.addEventListener("htmx:configRequest", (event) => {
    const scopedActionButton = closestElementWithinRoot(event.target, "[data-event-scoped-action]", root);
    if (scopedActionButton) {
      handleScopedActionConfigRequest(scopedActionButton, event);
    }
  });
};

/**
 * Binds global dismissal for event actions and table filters once.
 * @returns {void}
 */
const bindDocumentDropdownDismissHandler = () => {
  if (documentDismissHandlerBound) {
    return;
  }

  documentDismissHandlerBound = true;
  document.addEventListener("click", (event) => {
    const tableFilterMenu = closestElement(event.target, TABLE_FILTER_MENU_SELECTOR);
    if (tableFilterMenu) {
      closeTableFilterMenus(tableFilterMenu);
      return;
    }

    closeTableFilterMenus();

    if (
      closestElement(event.target, EVENTS_LIST_PAGE_SELECTOR) ||
      closestElement(event.target, EVENT_ACTION_DROPDOWN_SELECTOR) ||
      closestElement(event.target, EVENT_ACTIONS_BUTTON_SELECTOR)
    ) {
      return;
    }

    closeDropdowns(document);
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      closeTableFilterMenus();
      closeDropdowns(document, null, true);
    }
  });
};

/**
 * Closes event action dropdowns except an optional active dropdown.
 * @param {Document|Element} root Event list root.
 * @param {Element|null} exceptDropdown Dropdown to keep open.
 * @param {boolean} restoreFocus Whether to restore focus from a closed dropdown.
 * @returns {void}
 */
const closeDropdowns = (root, exceptDropdown = null, restoreFocus = false) => {
  root.querySelectorAll?.(`${EVENT_ACTION_DROPDOWN_SELECTOR}:not(.hidden)`).forEach((dropdown) => {
    if (dropdown === exceptDropdown) {
      return;
    }

    const actionsButton = getActionsDropdownButton(root, dropdown);
    const shouldRestoreFocus = restoreFocus && dropdown.contains(document.activeElement);
    setActionsDropdownExpanded(root, dropdown, false);
    if (shouldRestoreFocus) {
      actionsButton?.focus();
    }
  });
};

/**
 * Closes table filter disclosure elements except an optional active menu.
 * @param {Element|null} exceptMenu Menu to keep open.
 * @returns {void}
 */
const closeTableFilterMenus = (exceptMenu = null) => {
  document.querySelectorAll(`${TABLE_FILTER_MENU_SELECTOR}[open]`).forEach((menu) => {
    if (menu !== exceptMenu) {
      menu.open = false;
    }
  });
};

/**
 * Finds the disclosure button that owns an event actions dropdown.
 * @param {Document|Element} root Event list root.
 * @param {Element} dropdown Event actions dropdown.
 * @returns {HTMLElement|null} Owning disclosure button.
 */
const getActionsDropdownButton = (root, dropdown) =>
  root.querySelector?.(`${EVENT_ACTIONS_BUTTON_SELECTOR}[aria-controls="${CSS.escape(dropdown.id)}"]`) ??
  null;

/**
 * Toggles the event actions dropdown owned by a disclosure button.
 * @param {HTMLElement} button Actions disclosure button.
 * @param {Document|Element} root Event list root.
 * @returns {void}
 */
const handleActionsMenuClick = (button, root) => {
  const eventId = button.dataset.eventId;
  const dropdown = getElementById(root, `dropdown-actions-${eventId}`);
  if (!dropdown) {
    return;
  }

  const shouldOpen = isElementHidden(dropdown);
  closeDropdowns(root, dropdown);
  setActionsDropdownExpanded(root, dropdown, shouldOpen);
};

/**
 * Reports the result of a row-level ticket allocation action.
 * @param {HTMLElement} form Ticket allocation form or button.
 * @param {Event} event HTMX after-request event.
 * @returns {void}
 */
const handleRowTicketActionAfterRequest = (form, event) => {
  const xhr = event.detail?.xhr;
  const conflict = xhr?.status === 409 ? parseJsonText(xhr.responseText, {})?.conflict : null;
  const conflictMessage = Object.hasOwn(ROW_TICKET_CONFLICT_MESSAGES, conflict)
    ? ROW_TICKET_CONFLICT_MESSAGES[conflict]
    : null;

  handleHtmxResponse({
    xhr,
    successMessage: form.dataset.successMessage || "",
    errorMessage:
      conflictMessage || form.dataset.errorMessage || "Something went wrong. Please try again later.",
  });

  // Capacity conflicts can promote waitlist users, so refresh views to show current availability
  if (conflictMessage) {
    ROW_TICKET_CONFLICT_REFRESH_EVENTS.forEach((eventName) => {
      window.htmx?.trigger?.(document.body, eventName);
    });
  }
};

/**
 * Reports the completed event or series action.
 * @param {HTMLElement} button Scoped action button.
 * @param {Event} event HTMX after-request event.
 * @returns {void}
 */
const handleScopedActionAfterRequest = (button, event) => {
  const isSeriesRequest = button.dataset.requestScope === "series";
  delete button.dataset.requestPath;
  delete button.dataset.requestScope;

  handleHtmxResponse({
    xhr: event.detail?.xhr,
    successMessage: isSeriesRequest ? button.dataset.seriesSuccessMessage : button.dataset.successMessage,
    errorMessage: isSeriesRequest ? button.dataset.seriesErrorMessage : button.dataset.errorMessage,
  });
};

/**
 * Confirms whether an event action applies to one event or its series.
 * @param {HTMLElement} button Scoped action button.
 * @returns {Promise<void>}
 */
const handleScopedActionClick = async (button) => {
  let scope = "this";
  if (button.dataset.hasRelatedEvents === "true") {
    scope = await confirmSeriesAction({
      message: button.dataset.seriesMessage,
      confirmText: button.dataset.currentScopeText,
      denyText: button.dataset.seriesScopeText,
    });
    if (!scope) {
      return;
    }
  } else {
    const confirmed = await confirmAction({
      message: button.dataset.singleMessage,
      confirmText: button.dataset.confirmText,
      cancelText: button.dataset.cancelText,
    });
    if (!confirmed) {
      return;
    }
  }

  const url = button.dataset.actionUrl;
  button.dataset.requestPath = scope === "series" ? `${url}?scope=series` : url;
  button.dataset.requestScope = scope;
  htmx.trigger(button, "confirmed");
};

/**
 * Rewrites a scoped action request with its confirmed target path.
 * @param {HTMLElement} button Scoped action button.
 * @param {Event} event HTMX request configuration event.
 * @returns {void}
 */
const handleScopedActionConfigRequest = (button, event) => {
  const requestPath = button.dataset.requestPath;
  if (requestPath) {
    event.detail.path = requestPath;
  }
};

/**
 * Initializes all declarative events list behavior roots.
 * @param {Document|Element} root Root element to scan from.
 * @returns {void}
 */
const initializeEventsListPageRoots = (root = document) => {
  initializeRowTicketControls(root);
  initializeMatchingRoots(root, EVENTS_LIST_PAGE_SELECTOR, initializeEventsListPage);
};

/**
 * Prepares one row ticket assignment select and its submit button.
 *
 * Selects the sole assignable tier when the template left nothing selected,
 * and disables the form without an eligible tier.
 * @param {Element} ticketTypeInput Ticket type select element.
 * @returns {void}
 */
const initializeRowTicketControl = (ticketTypeInput) => {
  if (!(ticketTypeInput instanceof HTMLSelectElement)) {
    return;
  }

  const form = ticketTypeInput.closest("form");
  const emptyState = form?.querySelector(ROW_TICKET_EMPTY_SELECTOR);
  const submitButton = form?.querySelector(ROW_TICKET_SUBMIT_SELECTOR);
  const assignableOptions = Array.from(ticketTypeInput.options).filter(
    (option) => option.value !== "" && !option.disabled,
  );
  const hasAssignableTicketType = assignableOptions.length > 0;

  if (ticketTypeInput.value === "" && assignableOptions.length === 1) {
    ticketTypeInput.value = assignableOptions[0].value;
  }
  ticketTypeInput.disabled = !hasAssignableTicketType;
  if (submitButton instanceof HTMLButtonElement) {
    submitButton.disabled = submitButton.disabled || !hasAssignableTicketType;
  }
  if (emptyState instanceof HTMLElement) {
    setElementHidden(emptyState, hasAssignableTicketType);
  }
};

/**
 * Initializes row ticket assignment controls.
 * @param {Document|Element} root Root element to scan from.
 * @returns {void}
 */
const initializeRowTicketControls = (root) => {
  initializeMatchingRoots(root, ROW_TICKET_TYPE_SELECTOR, initializeRowTicketControl);
};

/**
 * Closes an invitation request dropdown before opening its answers modal.
 * @param {HTMLElement} trigger Answers modal trigger.
 * @param {Document|Element} root Event list root.
 * @returns {HTMLElement} Element that should regain focus when the modal closes.
 */
const prepareInvitationRequestAnswersOpen = (trigger, root) => {
  const dropdown = closestElementWithinRoot(trigger, EVENT_ACTION_DROPDOWN_SELECTOR, root);
  if (!dropdown) {
    return trigger;
  }

  const actionsButton = getActionsDropdownButton(root, dropdown);
  closeDropdowns(root);
  return actionsButton ?? trigger;
};

/**
 * Synchronizes an actions dropdown with its disclosure button.
 * @param {Document|Element} root Event list root.
 * @param {Element} dropdown Event actions dropdown.
 * @param {boolean} expanded Whether the dropdown is expanded.
 * @returns {void}
 */
const setActionsDropdownExpanded = (root, dropdown, expanded) => {
  setElementHidden(dropdown, !expanded);
  getActionsDropdownButton(root, dropdown)?.setAttribute("aria-expanded", String(expanded));
};

bindDocumentDropdownDismissHandler();
initializeOnReadyAndHtmxLoad(initializeEventsListPageRoots);

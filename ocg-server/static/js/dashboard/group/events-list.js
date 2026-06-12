import { confirmAction, confirmSeriesAction, handleHtmxResponse } from "/static/js/common/alerts.js";
import {
  closestElement,
  closestElementWithinRoot,
  initializeMatchingRoots,
  initializeOnReadyAndHtmxLoad,
  isElementHidden,
  setElementHidden,
} from "/static/js/common/dom.js";

const initializedRoots = new WeakSet();
let documentDismissHandlerBound = false;
const EVENTS_LIST_PAGE_SELECTOR = "[data-events-list-page]";
const EVENT_ACTION_DROPDOWN_SELECTOR = "[data-event-actions-dropdown]";
const EVENT_ACTIONS_BUTTON_SELECTOR = ".btn-actions";
const INVITATION_REQUEST_ACTION_SELECTOR = "[data-invitation-request-action]";

const closeDropdowns = (root, exceptDropdown = null) => {
  root.querySelectorAll?.(`${EVENT_ACTION_DROPDOWN_SELECTOR}:not(.hidden)`).forEach((dropdown) => {
    if (dropdown !== exceptDropdown) {
      setElementHidden(dropdown, true);
    }
  });
};

const handleActionsMenuClick = (button, root) => {
  const eventId = button.dataset.eventId;
  const dropdown =
    root.getElementById?.(`dropdown-actions-${eventId}`) ||
    root.querySelector?.(`#dropdown-actions-${CSS.escape(eventId)}`);
  if (!dropdown) {
    return;
  }

  const shouldOpen = isElementHidden(dropdown);
  closeDropdowns(root, dropdown);
  setElementHidden(dropdown, !shouldOpen);
};

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

const handleScopedActionConfigRequest = (button, event) => {
  const requestPath = button.dataset.requestPath;
  if (requestPath) {
    event.detail.path = requestPath;
  }
};

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

const handleInvitationRequestAfterRequest = (button, event) => {
  handleHtmxResponse({
    xhr: event.detail?.xhr,
    successMessage: button.dataset.successMessage || "",
    errorMessage: button.dataset.errorMessage || "Something went wrong. Please try again later.",
  });
};

/**
 * Closes open event action dropdowns when clicking outside all event lists.
 * @returns {void}
 */
const bindDocumentDropdownDismissHandler = () => {
  if (documentDismissHandlerBound) {
    return;
  }

  documentDismissHandlerBound = true;
  document.addEventListener("click", (event) => {
    if (
      closestElement(event.target, EVENTS_LIST_PAGE_SELECTOR) ||
      closestElement(event.target, EVENT_ACTION_DROPDOWN_SELECTOR) ||
      closestElement(event.target, EVENT_ACTIONS_BUTTON_SELECTOR)
    ) {
      return;
    }

    closeDropdowns(document);
  });
};

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

  root.addEventListener("click", (event) => {
    const actionsButton = closestElementWithinRoot(event.target, EVENT_ACTIONS_BUTTON_SELECTOR, root);
    if (actionsButton) {
      handleActionsMenuClick(actionsButton, root);
      return;
    }

    const scopedActionButton = closestElementWithinRoot(event.target, "[data-event-scoped-action]", root);
    if (scopedActionButton) {
      handleScopedActionClick(scopedActionButton);
      return;
    }

    if (!closestElementWithinRoot(event.target, EVENT_ACTION_DROPDOWN_SELECTOR, root)) {
      closeDropdowns(root);
    }
  });

  root.addEventListener("htmx:configRequest", (event) => {
    const scopedActionButton = closestElementWithinRoot(event.target, "[data-event-scoped-action]", root);
    if (scopedActionButton) {
      handleScopedActionConfigRequest(scopedActionButton, event);
    }
  });

  root.addEventListener("htmx:afterRequest", (event) => {
    const scopedActionButton = closestElementWithinRoot(event.target, "[data-event-scoped-action]", root);
    if (scopedActionButton) {
      handleScopedActionAfterRequest(scopedActionButton, event);
      return;
    }

    const invitationRequestButton = closestElementWithinRoot(
      event.target,
      INVITATION_REQUEST_ACTION_SELECTOR,
      root,
    );
    if (invitationRequestButton) {
      handleInvitationRequestAfterRequest(invitationRequestButton, event);
    }
  });
};

/**
 * Initializes all declarative events list behavior roots.
 * @param {Document|Element} root - Root element to scan from.
 * @returns {void}
 */
const initializeEventsListPageRoots = (root = document) => {
  initializeMatchingRoots(root, EVENTS_LIST_PAGE_SELECTOR, initializeEventsListPage);
};

initializeOnReadyAndHtmxLoad(initializeEventsListPageRoots);

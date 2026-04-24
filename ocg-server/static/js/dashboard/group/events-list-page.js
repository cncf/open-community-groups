import { confirmAction, confirmSeriesAction, handleHtmxResponse } from "/static/js/common/alerts.js";

const initializedRoots = new WeakSet();
const EVENT_ACTION_DROPDOWN_SELECTOR = "[data-event-actions-dropdown]";

const closestWithinRoot = (target, selector, root) => {
  const element = target instanceof Element ? target.closest(selector) : null;
  if (!element) {
    return null;
  }
  return root === document || root.contains(element) ? element : null;
};

const closeDropdowns = (root, exceptDropdown = null) => {
  root.querySelectorAll?.(`${EVENT_ACTION_DROPDOWN_SELECTOR}:not(.hidden)`).forEach((dropdown) => {
    if (dropdown !== exceptDropdown) {
      dropdown.classList.add("hidden");
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

  const shouldOpen = dropdown.classList.contains("hidden");
  closeDropdowns(root, dropdown);
  dropdown.classList.toggle("hidden", !shouldOpen);
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

export const initializeEventsListPage = (root = document) => {
  if (!root || initializedRoots.has(root)) {
    return;
  }

  initializedRoots.add(root);

  root.addEventListener("click", (event) => {
    const actionsButton = closestWithinRoot(event.target, ".btn-actions", root);
    if (actionsButton) {
      handleActionsMenuClick(actionsButton, root);
      return;
    }

    const scopedActionButton = closestWithinRoot(event.target, "[data-event-scoped-action]", root);
    if (scopedActionButton) {
      handleScopedActionClick(scopedActionButton);
      return;
    }

    if (!closestWithinRoot(event.target, EVENT_ACTION_DROPDOWN_SELECTOR, root)) {
      closeDropdowns(root);
    }
  });

  root.addEventListener("htmx:configRequest", (event) => {
    const scopedActionButton = closestWithinRoot(event.target, "[data-event-scoped-action]", root);
    if (scopedActionButton) {
      handleScopedActionConfigRequest(scopedActionButton, event);
    }
  });

  root.addEventListener("htmx:afterRequest", (event) => {
    const scopedActionButton = closestWithinRoot(event.target, "[data-event-scoped-action]", root);
    if (scopedActionButton) {
      handleScopedActionAfterRequest(scopedActionButton, event);
    }
  });
};

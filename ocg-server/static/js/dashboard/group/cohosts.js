import { confirmAction, handleHtmxResponse } from "/static/js/common/alerts.js";
import {
  closestElementWithinRoot,
  initializeMatchingRoots,
  initializeOnReadyAndHtmxLoad,
  markDatasetReady,
} from "/static/js/common/dom.js";
import { escapeHtml } from "/static/js/common/trusted-html.js";

// Alert shown when a co-host action request is rejected.
const ACTION_ERROR_MESSAGE =
  "Something went wrong updating this co-hosting invitation. Please try again later.";
// Selector for co-host action buttons in the list.
const ACTION_SELECTOR = "[data-cohost-action]";
// Alert shown when the connection fails and the action outcome is unknown.
const ACTION_UNCONFIRMED_MESSAGE =
  "We could not confirm this co-hosting update. Please refresh the page before trying again.";
// Selector for the co-hosts list root.
const COHOSTS_LIST_SELECTOR = "[data-group-cohosts-list]";
// Success alerts by co-host action.
const SUCCESS_MESSAGES = {
  approve: "Co-hosting invitation approved.",
  cancel: "Co-hosting canceled.",
  reject: "Co-hosting invitation rejected.",
};

/**
 * Initializes the group co-host invitations list actions.
 * @param {Element} root Co-hosts list root.
 * @returns {void}
 */
export const initializeGroupCohostsList = (root) => {
  if (!markDatasetReady(root, "groupCohostsReady")) {
    return;
  }

  // Delegate action clicks and responses so swapped rows keep working.
  root.addEventListener("click", (event) => {
    const button = closestElementWithinRoot(event.target, ACTION_SELECTOR, root);
    if (button instanceof HTMLButtonElement) {
      void handleCohostActionClick(button);
    }
  });

  root.addEventListener("htmx:afterRequest", (event) => {
    const button = closestElementWithinRoot(event.target, ACTION_SELECTOR, root);
    if (button instanceof HTMLButtonElement) {
      handleCohostActionResponse(button, event);
    }
  });
};

/**
 * Builds the approval confirmation HTML listing what approving implies.
 * @returns {string} Escaped confirmation HTML.
 */
const buildApproveConfirmationHtml = () => {
  const consequences = [
    "The event appears on your group page and credits you on its page and cards.",
    "When it is published, your members are notified as if it were your own event.",
    "The owning group keeps managing and operating it, and you get no access to it.",
    'It is counted only under "Co-hosted events" in your analytics.',
    "You can cancel later, and the owning group's admins will be notified.",
  ];

  return `<div class="text-left">
    <p>${escapeHtml("Approve this co-hosting invitation?")}</p>
    <ul class="mt-4 list-disc space-y-2 ps-5 text-sm">
      ${consequences.map((item) => `<li>${escapeHtml(item)}</li>`).join("")}
    </ul>
  </div>`;
};

/**
 * Asks the user to confirm a co-host action.
 * @param {string} action Co-host action: approve, cancel, or reject.
 * @returns {Promise<boolean>} True when the user confirms.
 */
const confirmCohostAction = (action) => {
  if (action === "approve") {
    return confirmAction({
      message: buildApproveConfirmationHtml(),
      confirmText: "Approve",
      withHtml: true,
    });
  }

  if (action === "cancel") {
    return confirmAction({
      message: "Cancel co-hosting for this event? The owning group's admins will be notified.",
      confirmText: "Cancel co-hosting",
      cancelText: "Keep co-hosting",
    });
  }

  return confirmAction({
    message: "Reject this co-hosting invitation? The owning group's admins will be notified.",
    confirmText: "Reject",
  });
};

/**
 * Confirms a co-host action and lets HTMX send it.
 * @param {HTMLButtonElement} button Clicked co-host action button.
 * @returns {Promise<void>}
 */
const handleCohostActionClick = async (button) => {
  const action = button.dataset.cohostAction;
  if (button.disabled || !action) {
    return;
  }

  const confirmed = await confirmCohostAction(action);
  if (confirmed) {
    htmx.trigger(button, "confirmed");
  }
};

/**
 * Shows the outcome alert for a finished co-host action request.
 * @param {HTMLButtonElement} button Co-host action button that sent the request.
 * @param {CustomEvent} event HTMX after request event.
 * @returns {void}
 */
const handleCohostActionResponse = (button, event) => {
  const xhr = event.detail?.xhr;

  // Warn that the request may have been applied before the connection failed.
  if (!xhr?.status) {
    handleHtmxResponse({ xhr: null, successMessage: "", errorMessage: ACTION_UNCONFIRMED_MESSAGE });
    return;
  }

  handleHtmxResponse({
    xhr,
    successMessage: SUCCESS_MESSAGES[button.dataset.cohostAction] || "",
    errorMessage: ACTION_ERROR_MESSAGE,
  });
};

/**
 * Initializes every co-hosts list inside a root.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const initializeGroupCohostsRoots = (root = document) => {
  initializeMatchingRoots(root, COHOSTS_LIST_SELECTOR, initializeGroupCohostsList);
};

initializeOnReadyAndHtmxLoad(initializeGroupCohostsRoots);

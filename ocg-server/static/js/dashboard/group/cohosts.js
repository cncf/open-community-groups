import { confirmAction, handleHtmxResponse } from "/static/js/common/alerts.js";
import {
  closestElementWithinRoot,
  initializeMatchingRoots,
  initializeOnReadyAndHtmxLoad,
  markDatasetReady,
} from "/static/js/common/dom.js";
import { ocgFetch } from "/static/js/common/fetch.js";
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

  // Delegate action clicks so swapped rows keep working.
  root.addEventListener("click", (event) => {
    const button = closestElementWithinRoot(event.target, ACTION_SELECTOR, root);
    if (button instanceof HTMLButtonElement) {
      void handleCohostAction(button);
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
 * Dispatches the events listed in the response HX-Trigger header on the body.
 * @param {Response} response Co-host action response.
 * @returns {void}
 */
const dispatchHtmxTriggers = (response) => {
  const triggerHeader = response.headers.get("HX-Trigger");
  if (!triggerHeader) {
    return;
  }

  triggerHeader
    .split(",")
    .map((eventName) => eventName.trim())
    .filter(Boolean)
    .forEach((eventName) => {
      document.body.dispatchEvent(new Event(eventName, { bubbles: true }));
    });
};

/**
 * Confirms and sends a co-host action, blocking repeat clicks while pending.
 * @param {HTMLButtonElement} button Clicked co-host action button.
 * @returns {Promise<void>}
 */
const handleCohostAction = async (button) => {
  if (button.disabled) {
    return;
  }

  const action = button.dataset.cohostAction;
  const url = button.dataset.cohostUrl;
  if (!action || !url) {
    return;
  }

  const confirmed = await confirmCohostAction(action);
  if (!confirmed) {
    return;
  }

  // Block repeat clicks while the request is pending.
  button.disabled = true;
  button.setAttribute("aria-busy", "true");

  try {
    const response = await ocgFetch(url, {
      credentials: "same-origin",
      method: "PUT",
    });

    // Reuse the HTMX response alerts with an xhr-like adapter.
    const responseText = await response.text();
    const ok = handleHtmxResponse({
      xhr: {
        status: response.status,
        responseText,
        getResponseHeader: (name) => response.headers.get(name),
      },
      successMessage: SUCCESS_MESSAGES[action] || "",
      errorMessage: ACTION_ERROR_MESSAGE,
    });

    // Refresh the list only after a successful action.
    if (ok) {
      dispatchHtmxTriggers(response);
    }
  } catch {
    // Warn that the request may have been applied before the connection failed.
    handleHtmxResponse({ xhr: null, successMessage: "", errorMessage: ACTION_UNCONFIRMED_MESSAGE });
  } finally {
    button.disabled = false;
    button.removeAttribute("aria-busy");
  }
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

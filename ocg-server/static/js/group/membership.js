import {
  showConfirmAlert,
  showSigninPrompt,
  handleHtmxResponse,
  waitForAlertToClose,
} from "/static/js/common/alerts.js";
import {
  closestElement,
  getElementById,
  initializeOnReadyAndHtmxLoad,
  isElementHidden,
  markDatasetReady,
  setElementHidden,
} from "/static/js/common/dom.js";
import { resolveUserLoggedIn } from "/static/js/common/user-session.js";
import { isSuccessfulXHR, parseJsonText } from "/static/js/common/utils.js";

const MEMBERSHIP_CONTAINER_SELECTOR = "#membership-container";
const GROUP_ACTIONS_MENU_SELECTOR = "[data-group-actions-menu]";

// Alert copy for each membership action button, keyed by button id.
const ACTION_MESSAGES = {
  "join-btn": {
    errorMessage: "Something went wrong joining this group. Please try again later.",
    successMessage: "You have successfully joined this group.",
  },
  "leave-btn": {
    errorMessage: "Something went wrong leaving this group. Please try again later.",
    successMessage: "You have successfully left this group.",
  },
};

// Membership buttons that can receive focus once an action settles, in order.
const ACTION_BUTTON_IDS = ["signin-btn", "join-btn", "leave-btn"];

// Container dataset key marking a join or leave request whose focus is pending.
const ACTION_PENDING_KEY = "membershipActionPending";

/** Containers whose logged-out state was already looked up. */
const sessionCheckedContainers = new WeakSet();

/**
 * Returns all membership containers within a root node.
 * @param {Document|Element} root - Root node to search
 * @returns {HTMLElement[]} Membership containers
 */
const getMembershipContainers = (root) => {
  if (!root) {
    return [];
  }

  const containers = new Set();
  if (root instanceof HTMLElement && root.matches(MEMBERSHIP_CONTAINER_SELECTOR)) {
    containers.add(root);
  }

  root.querySelectorAll?.(MEMBERSHIP_CONTAINER_SELECTOR).forEach((container) => {
    containers.add(container);
  });

  return Array.from(containers);
};

/**
 * Initializes membership container state. Logged-out visitors send no membership
 * check, so their container shows the sign-in action as soon as the login state
 * is known.
 * @param {HTMLElement} container - Membership container element
 */
const initializeMembershipContainer = (container) => {
  markDatasetReady(container, "membershipReady");

  if (sessionCheckedContainers.has(container)) {
    return;
  }
  sessionCheckedContainers.add(container);
  resolveUserLoggedIn().then((loggedIn) => {
    if (loggedIn === false && container.isConnected) {
      showMembershipState(container, null);
    }
  });
};

/**
 * Handles membership check responses.
 * @param {Event} event - htmx:afterRequest event
 */
const handleMembershipCheckResponse = (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement) || target.id !== "membership-checker") {
    return;
  }

  const container = closestElement(target, MEMBERSHIP_CONTAINER_SELECTOR);
  if (!container) {
    return;
  }

  const xhr = event.detail?.xhr;
  showMembershipState(container, isSuccessfulXHR(xhr) ? parseJsonText(xhr.responseText, null) : null);
};

/**
 * Shows the loading state while a join or leave request is in flight and marks
 * the container so focus returns to the membership action once it settles.
 * @param {HTMLElement} target - Event target
 */
const handleActionBeforeRequest = (target) => {
  if (!getActionMessages(target.id)) {
    return;
  }

  const container = closestElement(target, MEMBERSHIP_CONTAINER_SELECTOR);
  const loadingButton = container ? getElementById(container, "loading-btn") : null;
  if (!loadingButton) {
    return;
  }

  setElementHidden(target, true);
  setElementHidden(loadingButton, false);
  container.dataset[ACTION_PENDING_KEY] = "true";
};

/**
 * Handles join or leave responses. Success re-checks membership, which shows
 * and focuses the next action; failure restores and focuses the same action.
 * @param {Event} event - htmx:afterRequest event
 */
const handleActionAfterRequest = (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement)) {
    return;
  }

  const messages = getActionMessages(target.id);
  const container = messages ? closestElement(target, MEMBERSHIP_CONTAINER_SELECTOR) : null;
  const loadingButton = container ? getElementById(container, "loading-btn") : null;
  if (!loadingButton) {
    return;
  }

  const ok = handleHtmxResponse({ xhr: event.detail?.xhr, ...messages });
  if (ok) {
    document.body.dispatchEvent(new Event("membership-changed"));
    return;
  }

  setElementHidden(loadingButton, true);
  setElementHidden(target, false);
  restoreActionFocus(container);
};

/**
 * Returns the alert copy for a membership action button.
 * @param {string} buttonId - Button id
 * @returns {{errorMessage: string, successMessage: string}|null} Alert copy, or
 * null when the button is not a join or leave action
 */
const getActionMessages = (buttonId) =>
  Object.hasOwn(ACTION_MESSAGES, buttonId) ? ACTION_MESSAGES[buttonId] : null;

/**
 * Checks whether keyboard focus was lost while a membership action ran: nothing
 * or the body is focused, or the focused element was removed or hidden.
 * @param {HTMLElement} container - Membership container element
 * @returns {boolean} Whether focus needs to be restored
 */
const isActionFocusLost = (container) => {
  const activeElement = document.activeElement;
  if (!activeElement || activeElement === document.body || !activeElement.isConnected) {
    return true;
  }

  // Firefox can keep a hidden button as the active element.
  return container.contains(activeElement) && isElementHidden(activeElement);
};

/**
 * Moves focus to the visible membership action after a join or leave request
 * settles. It waits for the result alert to close first, so the alert does not
 * restore focus to the hidden button, and leaves focus alone when the user
 * moved it elsewhere or no action request is pending (initial check).
 * @param {HTMLElement} container - Membership container element
 * @returns {Promise<void>} Promise resolved once focus is handled
 */
const restoreActionFocus = async (container) => {
  if (container.dataset[ACTION_PENDING_KEY] !== "true") {
    return;
  }
  delete container.dataset[ACTION_PENDING_KEY];

  await waitForAlertToClose();
  if (!isActionFocusLost(container)) {
    return;
  }

  const actionButton = ACTION_BUTTON_IDS.map((buttonId) => getElementById(container, buttonId)).find(
    (button) => button && !isElementHidden(button),
  );
  actionButton?.focus();
};

/**
 * Shows the membership action that matches a check response: leave for members,
 * join for other logged-in users, and sign in when there is no usable response.
 * @param {HTMLElement} container - Membership container element
 * @param {{is_member: boolean}|null} response - Parsed membership response
 */
const showMembershipState = (container, response) => {
  const loadingButton = getElementById(container, "loading-btn");
  const signinButton = getElementById(container, "signin-btn");
  const joinButton = getElementById(container, "join-btn");
  const leaveButton = getElementById(container, "leave-btn");

  if (!loadingButton || !signinButton || !joinButton || !leaveButton) {
    return;
  }

  setElementHidden(loadingButton, true);
  setElementHidden(signinButton, true);
  setElementHidden(joinButton, true);
  setElementHidden(leaveButton, true);

  let visibleButton = signinButton;
  if (response) {
    visibleButton = response.is_member ? leaveButton : joinButton;
  }
  setElementHidden(visibleButton, false);

  restoreActionFocus(container);
};

/**
 * Handles htmx:beforeRequest events for membership buttons.
 * @param {Event} event - htmx:beforeRequest event
 */
const handleBeforeRequest = (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement)) {
    return;
  }

  if (!closestElement(target, MEMBERSHIP_CONTAINER_SELECTOR)) {
    return;
  }

  handleActionBeforeRequest(target);
};

/**
 * Handles htmx:afterRequest events for membership components.
 * @param {Event} event - htmx:afterRequest event
 */
const handleAfterRequest = (event) => {
  handleMembershipCheckResponse(event);
  handleActionAfterRequest(event);
};

/**
 * Handles click events for membership actions.
 * @param {MouseEvent} event - Click event
 */
const handleMembershipClick = (event) => {
  const target = event.target;
  if (!(target instanceof Element)) {
    return;
  }

  document.querySelectorAll(`${GROUP_ACTIONS_MENU_SELECTOR}[open]`).forEach((actionsMenu) => {
    if (actionsMenu instanceof HTMLDetailsElement && !actionsMenu.contains(target)) {
      actionsMenu.open = false;
    }
  });

  if (!closestElement(event.target, MEMBERSHIP_CONTAINER_SELECTOR)) {
    return;
  }

  const signinButton = closestElement(event.target, "#signin-btn");
  if (signinButton) {
    showSigninPrompt("join this group", signinButton.dataset.path || window.location.pathname);
    return;
  }

  const leaveButton = closestElement(event.target, "#leave-btn");
  if (leaveButton) {
    showConfirmAlert("Are you sure you want to leave this group?", "leave-btn", "Yes");
  }
};

/**
 * Initializes membership handlers for the current page.
 * @param {Document|Element} root - Root node to search
 */
const initializeMembership = (root = document) => {
  getMembershipContainers(root).forEach(initializeMembershipContainer);

  if (!markDatasetReady(document.documentElement, "membershipListenersReady")) {
    return;
  }

  document.addEventListener("htmx:beforeRequest", handleBeforeRequest);
  document.addEventListener("htmx:afterRequest", handleAfterRequest);
  document.addEventListener("click", handleMembershipClick);
};

initializeOnReadyAndHtmxLoad(initializeMembership);

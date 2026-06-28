import { showConfirmAlert, showInfoAlert, handleHtmxResponse } from "/static/js/common/alerts.js";
import { isSuccessfulXHRStatus } from "/static/js/common/common.js";
import {
  closestElement,
  getElementById,
  initializeOnReadyAndHtmxLoad,
  markDatasetReady,
  setElementHidden,
} from "/static/js/common/dom.js";
import { parseJsonText } from "/static/js/common/utils.js";

const MEMBERSHIP_CONTAINER_SELECTOR = "#membership-container";
const GROUP_ACTIONS_MENU_SELECTOR = "[data-group-actions-menu]";

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
 * Initializes membership container state.
 * @param {HTMLElement} container - Membership container element
 */
const initializeMembershipContainer = (container) => {
  markDatasetReady(container, "membershipReady");
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

  const loadingButton = getElementById(container, "loading-btn");
  const signinButton = getElementById(container, "signin-btn");
  const joinButton = getElementById(container, "join-btn");
  const pendingButton = getElementById(container, "pending-btn");
  const leaveButton = getElementById(container, "leave-btn");

  if (!loadingButton || !signinButton || !joinButton || !pendingButton || !leaveButton) {
    return;
  }

  setElementHidden(loadingButton, true);
  setElementHidden(signinButton, true);
  setElementHidden(joinButton, true);
  setElementHidden(pendingButton, true);
  setElementHidden(leaveButton, true);

  const xhr = event.detail?.xhr;

  if (isSuccessfulXHRStatus(xhr?.status)) {
    const response = parseJsonText(xhr.responseText, null);
    if (!response) {
      setElementHidden(signinButton, false);
      return;
    }

    if (response.is_member) {
      setElementHidden(leaveButton, false);
    } else if (response.has_pending_request) {
      setElementHidden(pendingButton, false);
    } else {
      setElementHidden(joinButton, false);
    }
    return;
  }

  setElementHidden(signinButton, false);
};

/**
 * Handles join button beforeRequest state.
 * @param {HTMLElement} target - Event target
 */
const handleJoinBeforeRequest = (target) => {
  if (target.id !== "join-btn") {
    return;
  }

  const container = closestElement(target, MEMBERSHIP_CONTAINER_SELECTOR);
  const loadingButton = container ? getElementById(container, "loading-btn") : null;
  if (!loadingButton) {
    return;
  }

  setElementHidden(target, true);
  setElementHidden(loadingButton, false);
};

/**
 * Handles leave button beforeRequest state.
 * @param {HTMLElement} target - Event target
 */
const handleLeaveBeforeRequest = (target) => {
  if (target.id !== "leave-btn") {
    return;
  }

  const container = closestElement(target, MEMBERSHIP_CONTAINER_SELECTOR);
  const loadingButton = container ? getElementById(container, "loading-btn") : null;
  if (!loadingButton) {
    return;
  }

  setElementHidden(target, true);
  setElementHidden(loadingButton, false);
};

/**
 * Handles join button afterRequest state.
 * @param {Event} event - htmx:afterRequest event
 */
const handleJoinAfterRequest = (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement) || target.id !== "join-btn") {
    return;
  }

  const container = closestElement(target, MEMBERSHIP_CONTAINER_SELECTOR);
  if (!container) {
    return;
  }

  const loadingButton = getElementById(container, "loading-btn");
  const joinButton = getElementById(container, "join-btn");
  const pendingButton = getElementById(container, "pending-btn");
  if (!loadingButton || !joinButton || !pendingButton) {
    return;
  }

  const xhr = event.detail?.xhr;
  const response = parseJsonText(xhr?.responseText, null);
  const requestedApproval = response?.status === "pending";
  const ok = handleHtmxResponse({
    xhr,
    successMessage: requestedApproval
      ? "Your request to join this group is pending approval."
      : "You have successfully joined this group.",
    errorMessage: "Something went wrong joining this group. Please try again later.",
  });
  if (ok) {
    setElementHidden(loadingButton, true);
    setElementHidden(pendingButton, !requestedApproval);
    document.body.dispatchEvent(new Event("membership-changed"));
  } else {
    setElementHidden(loadingButton, true);
    setElementHidden(joinButton, false);
  }
};

/**
 * Handles leave button afterRequest state.
 * @param {Event} event - htmx:afterRequest event
 */
const handleLeaveAfterRequest = (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement) || target.id !== "leave-btn") {
    return;
  }

  const container = closestElement(target, MEMBERSHIP_CONTAINER_SELECTOR);
  if (!container) {
    return;
  }

  const loadingButton = getElementById(container, "loading-btn");
  const leaveButton = getElementById(container, "leave-btn");
  if (!loadingButton || !leaveButton) {
    return;
  }

  const xhr = event.detail?.xhr;
  const ok = handleHtmxResponse({
    xhr,
    successMessage: "You have successfully left this group.",
    errorMessage: "Something went wrong leaving this group. Please try again later.",
  });
  if (ok) {
    document.body.dispatchEvent(new Event("membership-changed"));
  } else {
    setElementHidden(loadingButton, true);
    setElementHidden(leaveButton, false);
  }
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

  handleJoinBeforeRequest(target);
  handleLeaveBeforeRequest(target);
};

/**
 * Handles htmx:afterRequest events for membership components.
 * @param {Event} event - htmx:afterRequest event
 */
const handleAfterRequest = (event) => {
  handleMembershipCheckResponse(event);
  handleJoinAfterRequest(event);
  handleLeaveAfterRequest(event);
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
    const path = signinButton.dataset.path || window.location.pathname;
    const nextUrl = encodeURIComponent(path);
    showInfoAlert(
      `You need to be <a href='/log-in?next_url=${nextUrl}' class='underline font-medium' hx-boost='true'>logged in</a> to join this group.`,
      true,
    );
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

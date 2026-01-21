import { showConfirmAlert, showInfoAlert, handleHtmxResponse } from "/static/js/common/alerts.js";
import { isSuccessfulXHRStatus } from "/static/js/common/common.js";

const MEMBERSHIP_CONTAINER_SELECTOR = "#membership-container";

/**
 * Returns all membership containers within a root node.
 * @param {Document|HTMLElement} root - Root node to search
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
  if (!container || container.dataset.membershipReady === "true") {
    return;
  }

  container.dataset.membershipReady = "true";
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

  const container = target.closest(MEMBERSHIP_CONTAINER_SELECTOR);
  if (!container) {
    return;
  }

  const loadingButton = container.querySelector("#loading-btn");
  const signinButton = container.querySelector("#signin-btn");
  const joinButton = container.querySelector("#join-btn");
  const leaveButton = container.querySelector("#leave-btn");

  if (!loadingButton || !signinButton || !joinButton || !leaveButton) {
    return;
  }

  loadingButton.classList.add("hidden");
  signinButton.classList.add("hidden");
  joinButton.classList.add("hidden");
  leaveButton.classList.add("hidden");

  const xhr = event.detail?.xhr;

  if (isSuccessfulXHRStatus(xhr?.status)) {
    try {
      const response = JSON.parse(xhr.responseText);

      if (response.is_member) {
        leaveButton.classList.remove("hidden");
      } else {
        joinButton.classList.remove("hidden");
      }
    } catch (error) {
      signinButton.classList.remove("hidden");
    }
    return;
  }

  signinButton.classList.remove("hidden");
};

/**
 * Handles join button beforeRequest state.
 * @param {HTMLElement} target - Event target
 */
const handleJoinBeforeRequest = (target) => {
  if (target.id !== "join-btn") {
    return;
  }

  const container = target.closest(MEMBERSHIP_CONTAINER_SELECTOR);
  const loadingButton = container?.querySelector("#loading-btn");
  if (!loadingButton) {
    return;
  }

  target.classList.add("hidden");
  loadingButton.classList.remove("hidden");
};

/**
 * Handles leave button beforeRequest state.
 * @param {HTMLElement} target - Event target
 */
const handleLeaveBeforeRequest = (target) => {
  if (target.id !== "leave-btn") {
    return;
  }

  const container = target.closest(MEMBERSHIP_CONTAINER_SELECTOR);
  const loadingButton = container?.querySelector("#loading-btn");
  if (!loadingButton) {
    return;
  }

  target.classList.add("hidden");
  loadingButton.classList.remove("hidden");
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

  const container = target.closest(MEMBERSHIP_CONTAINER_SELECTOR);
  if (!container) {
    return;
  }

  const loadingButton = container.querySelector("#loading-btn");
  const joinButton = container.querySelector("#join-btn");
  if (!loadingButton || !joinButton) {
    return;
  }

  const xhr = event.detail?.xhr;
  const ok = handleHtmxResponse({
    xhr,
    successMessage: "You have successfully joined this group.",
    errorMessage: "Something went wrong joining this group. Please try again later.",
  });
  if (ok) {
    document.body.dispatchEvent(new Event("membership-changed"));
  } else {
    loadingButton.classList.add("hidden");
    joinButton.classList.remove("hidden");
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

  const container = target.closest(MEMBERSHIP_CONTAINER_SELECTOR);
  if (!container) {
    return;
  }

  const loadingButton = container.querySelector("#loading-btn");
  const leaveButton = container.querySelector("#leave-btn");
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
    loadingButton.classList.add("hidden");
    leaveButton.classList.remove("hidden");
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

  if (!target.closest(MEMBERSHIP_CONTAINER_SELECTOR)) {
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

  if (!target.closest(MEMBERSHIP_CONTAINER_SELECTOR)) {
    return;
  }

  const signinButton = target.closest("#signin-btn");
  if (signinButton) {
    const path = signinButton.dataset.path || window.location.pathname;
    showInfoAlert(
      `You need to be <a href='/log-in?next_url=${path}' class='underline font-medium' hx-boost='true'>logged in</a> to join this group.`,
      true,
    );
    return;
  }

  const leaveButton = target.closest("#leave-btn");
  if (leaveButton) {
    showConfirmAlert("Are you sure you want to leave this group?", "leave-btn", "Yes");
  }
};

/**
 * Initializes membership handlers for the current page.
 * @param {Document|HTMLElement} root - Root node to search
 */
const initializeMembership = (root = document) => {
  getMembershipContainers(root).forEach(initializeMembershipContainer);

  if (document.body?.dataset.membershipListenersReady === "true") {
    return;
  }

  document.body.dataset.membershipListenersReady = "true";
  document.body.addEventListener("htmx:beforeRequest", handleBeforeRequest);
  document.body.addEventListener("htmx:afterRequest", handleAfterRequest);
  document.body.addEventListener("click", handleMembershipClick);
};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", () => initializeMembership(document));
} else {
  initializeMembership(document);
}

if (window.htmx && typeof htmx.onLoad === "function") {
  htmx.onLoad((element) => {
    if (element) {
      initializeMembership(element);
    }
  });
}

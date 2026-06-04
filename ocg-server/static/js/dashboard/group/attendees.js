import { createNotificationModal } from "/static/js/dashboard/group/notification-modal.js";
import { initializeQrCodeModal } from "/static/js/dashboard/group/qr-code-modal.js";
import "/static/js/common/user-search-field.js";
import { handleHtmxResponse, showErrorAlert } from "/static/js/common/alerts.js";
import {
  computeUserInitials,
  isSuccessfulXHRStatus,
  toggleModalVisibility,
} from "/static/js/common/common.js";
import { getElementById } from "/static/js/common/dom.js";
import { ocgFetch } from "/static/js/common/fetch.js";

const modalId = "attendee-notification-modal";
const formId = "attendee-notification-form";
const dataKey = "attendeeNotificationReady";
const refundModalId = "attendee-refund-modal";
const refundApproveButtonId = "attendee-refund-approve";
const refundRejectButtonId = "attendee-refund-reject";
const answersModalId = "attendee-answers-modal";
const attendeeActionsDropdownSelector = "[data-attendee-actions-dropdown]";
const attendeeRowActionsMenuSelector = "[data-attendee-row-actions-menu]";
const invitationModalId = "attendee-invitation-modal";
const invitationEmailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const resolveAttendeesRoot = (root = document) => {
  if (root instanceof Element && root.id === "attendees-content") {
    return root;
  }

  if (root instanceof Element) {
    return root.closest("#attendees-content") || root.querySelector("#attendees-content") || root;
  }

  return root.querySelector?.("#attendees-content") || root.body || root;
};

/**
 * Resolve the current refund review modal controls from the latest DOM.
 * @param {Document|Element} [root=document] Query root.
 * @returns {Object} Refund modal controls.
 */
const getRefundReviewControls = (root = document) => ({
  modal: getElementById(root, refundModalId),
  nameField: getElementById(root, "attendee-refund-name"),
  ticketField: getElementById(root, "attendee-refund-ticket"),
  amountField: getElementById(root, "attendee-refund-amount"),
  approveButton: getElementById(root, refundApproveButtonId),
  rejectButton: getElementById(root, refundRejectButtonId),
});

/**
 * Show the refund review modal if it is currently hidden.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const openRefundModal = (root = document) => {
  const modal = getElementById(root, refundModalId);
  if (modal?.classList.contains("hidden")) {
    toggleModalVisibility(refundModalId);
  }
};

/**
 * Hide the refund review modal if it is currently visible.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const closeRefundModal = (root = document) => {
  const modal = getElementById(root, refundModalId);
  if (modal && !modal.classList.contains("hidden")) {
    toggleModalVisibility(refundModalId);
  }
};

/**
 * Hide the attendee answers modal if it is currently visible.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const closeAnswersModal = (root = document) => {
  const modal = getElementById(root, answersModalId);
  if (modal && !modal.classList.contains("hidden")) {
    toggleModalVisibility(answersModalId);
  }
};

/**
 * Populate the attendee answers modal with a row's answer markup.
 * @param {HTMLElement} trigger Modal trigger.
 * @param {Document|Element} root Query root.
 * @returns {void}
 */
const populateAnswersModal = (trigger, root) => {
  const sourceId = trigger.dataset.attendeeAnswersSource;
  const source = sourceId ? getElementById(root, sourceId) : null;
  const content = getElementById(root, "attendee-answers-content");
  const name = getElementById(root, "attendee-answers-name");

  if (name) {
    name.textContent = trigger.dataset.attendeeName || "";
  }
  if (content) {
    content.innerHTML = source?.innerHTML || "";
  }
};

/**
 * Show the attendee answers modal if it is currently hidden.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const openAnswersModal = (root = document) => {
  const modal = getElementById(root, answersModalId);
  if (modal?.classList.contains("hidden")) {
    toggleModalVisibility(answersModalId);
  }
};

/**
 * Hide the attendee invitation modal if it is currently visible.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const closeInvitationModal = (root = document) => {
  const modal = getElementById(root, invitationModalId);
  if (modal && !modal.classList.contains("hidden")) {
    toggleModalVisibility(invitationModalId);
  }
};

/**
 * Validate an attendee invitation email candidate.
 * @param {string} email Email candidate.
 * @returns {boolean} True when the email can be submitted.
 */
const isValidInvitationEmail = (email) => invitationEmailPattern.test(email.trim());

/**
 * Resolve the invitation search field from the current modal.
 * @param {Document|Element} root Query root.
 * @returns {Element|null} Search field element.
 */
const getInvitationSearchField = (root) =>
  root.querySelector?.("user-search-field[data-attendee-invitation-search]") || null;

/**
 * Set which invitation field should be submitted.
 * @param {Document|Element} root Query root.
 * @param {"user"|"email"|""} field Active submission field.
 * @returns {void}
 */
const setInvitationSubmissionField = (root, field) => {
  const userInput = getElementById(root, "attendee-invitation-user-id");
  const emailInput = getElementById(root, "attendee-invitation-email");

  if (userInput) userInput.disabled = field !== "user";
  if (emailInput) emailInput.disabled = field !== "email";
};

/**
 * Clear the selected invitation user display.
 * @param {Document|Element} root Query root.
 * @returns {void}
 */
const clearInvitationSelectedUser = (root) => {
  const userInput = getElementById(root, "attendee-invitation-user-id");
  const emailInput = getElementById(root, "attendee-invitation-email");
  const selectedUser = getElementById(root, "attendee-invitation-selected-user");
  const searchField = getInvitationSearchField(root);

  if (userInput) userInput.value = "";
  if (emailInput) emailInput.value = "";
  setInvitationSubmissionField(root, "");
  selectedUser?.replaceChildren();
  if (typeof searchField?.clearSearch === "function") {
    searchField.clearSearch({ refocus: false });
  }
  updateInvitationSubmitState(root);
};

/**
 * Reset the attendee invitation form to its empty state.
 * @param {Document|Element} root Query root.
 * @returns {void}
 */
const resetInvitationForm = (root) => {
  const userInput = getElementById(root, "attendee-invitation-user-id");
  const emailInput = getElementById(root, "attendee-invitation-email");
  const selectedUser = getElementById(root, "attendee-invitation-selected-user");
  const searchField = getInvitationSearchField(root);

  if (userInput) userInput.value = "";
  if (emailInput) emailInput.value = "";
  setInvitationSubmissionField(root, "");
  selectedUser?.replaceChildren();
  if (typeof searchField?.clearSearch === "function") {
    searchField.clearSearch({ refocus: false });
  }
  updateInvitationSubmitState(root);
};

/**
 * Render the selected invitation user with the shared user chip style.
 * @param {Document|Element} root Query root.
 * @param {Object} user Selected user.
 * @returns {void}
 */
const renderInvitationSelectedUser = (root, user) => {
  const selectedUser = getElementById(root, "attendee-invitation-selected-user");
  if (!selectedUser) return;

  const pill = document.createElement("div");
  pill.className = "inline-flex items-center gap-2 bg-stone-100 rounded-full ps-1 pe-1 py-1";

  const avatar = document.createElement("logo-image");
  avatar.setAttribute("image-url", user.photo_url || "");
  avatar.setAttribute("placeholder", computeUserInitials(user.name, user.username, 2));
  avatar.setAttribute("size", "size-[24px]");
  avatar.setAttribute("font-size", "text-xs");
  avatar.setAttribute("hide-border", "true");

  const label = document.createElement("span");
  label.className = "text-sm text-stone-700 pe-2";
  label.textContent = user.name || user.username;

  const removeButton = document.createElement("button");
  removeButton.type = "button";
  removeButton.className = "p-1 hover:bg-stone-200 rounded-full transition-colors";
  removeButton.title = "Remove user";
  removeButton.setAttribute("data-attendee-invitation-clear-user", "");

  const removeIcon = document.createElement("div");
  removeIcon.className = "svg-icon size-3 icon-close bg-stone-600";

  removeButton.append(removeIcon);
  pill.append(avatar, label, removeButton);
  selectedUser.replaceChildren(pill);
};

/**
 * Render the selected invitation email with the shared chip style.
 * @param {Document|Element} root Query root.
 * @param {string} email Selected email.
 * @returns {void}
 */
const renderInvitationSelectedEmail = (root, email) => {
  const selectedUser = getElementById(root, "attendee-invitation-selected-user");
  if (!selectedUser) return;

  const pill = document.createElement("div");
  pill.className = "inline-flex items-center gap-2 bg-stone-100 rounded-full ps-1 pe-1 py-1";

  const iconBox = document.createElement("span");
  iconBox.className =
    "inline-flex size-[24px] shrink-0 items-center justify-center rounded-full bg-stone-200";

  const icon = document.createElement("div");
  icon.className = "svg-icon size-3.5 icon-email bg-stone-600";

  const label = document.createElement("span");
  label.className = "text-sm text-stone-700 pe-2";
  label.textContent = email;

  const removeButton = document.createElement("button");
  removeButton.type = "button";
  removeButton.className = "p-1 hover:bg-stone-200 rounded-full transition-colors";
  removeButton.title = "Remove email";
  removeButton.setAttribute("data-attendee-invitation-clear-user", "");

  const removeIcon = document.createElement("div");
  removeIcon.className = "svg-icon size-3 icon-close bg-stone-600";

  removeButton.append(removeIcon);
  iconBox.append(icon);
  pill.append(iconBox, label, removeButton);
  selectedUser.replaceChildren(pill);
};

/**
 * Enable the invitation submit button when a user or valid email is present.
 * @param {Document|Element} root Query root.
 * @returns {void}
 */
const updateInvitationSubmitState = (root) => {
  const form = getElementById(root, "attendee-invitation-form");
  const submit = getElementById(root, "submit-attendee-invitation");
  if (!form || !submit) return;

  const userId = getElementById(root, "attendee-invitation-user-id")?.value || "";
  const email = getElementById(root, "attendee-invitation-email")?.value.trim() || "";
  submit.disabled = userId === "" && !isValidInvitationEmail(email);
};

/**
 * Update hidden invitation fields from the current search query.
 * @param {Document|Element} root Query root.
 * @param {string} query Search query.
 * @returns {void}
 */
const updateInvitationQuery = (root, query) => {
  const userInput = getElementById(root, "attendee-invitation-user-id");
  const emailInput = getElementById(root, "attendee-invitation-email");
  const selectedUser = getElementById(root, "attendee-invitation-selected-user");
  if (!userInput || !emailInput) return;

  const email = query.trim();
  userInput.value = "";
  if (isValidInvitationEmail(email)) {
    emailInput.value = email;
    setInvitationSubmissionField(root, "email");
  } else {
    emailInput.value = "";
    setInvitationSubmissionField(root, "");
  }
  selectedUser?.replaceChildren();
  updateInvitationSubmitState(root);
};

/**
 * Select an email from the invitation dropdown.
 * @param {Document|Element} root Query root.
 * @param {string} email Selected email.
 * @returns {void}
 */
const selectInvitationEmail = (root, email) => {
  const userInput = getElementById(root, "attendee-invitation-user-id");
  const emailInput = getElementById(root, "attendee-invitation-email");
  if (!emailInput || !isValidInvitationEmail(email)) return;

  if (userInput) userInput.value = "";
  emailInput.value = email.trim();
  setInvitationSubmissionField(root, "email");
  renderInvitationSelectedEmail(root, email.trim());
  updateInvitationSubmitState(root);
};

/**
 * Update a refund modal action button label.
 * @param {HTMLElement | null} button
 * @param {string} label
 * @returns {void}
 */
const setRefundActionLabel = (button, label) => {
  const labelNode = button?.querySelector("[data-refund-action-label]");
  if (labelNode) {
    labelNode.textContent = label;
    return;
  }

  if (button) {
    button.textContent = label;
  }
};

/**
 * Re-process a refund action button after its HTMX attributes change.
 * @param {HTMLElement | null} button
 * @returns {void}
 */
const processRefundActionButton = (button) => {
  if (button && window.htmx && typeof window.htmx.process === "function") {
    window.htmx.process(button);
  }
};

/**
 * Close the attendee actions dropdown.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const closeAttendeeActionsDropdown = (root = document) => {
  root.querySelector?.(attendeeActionsDropdownSelector)?.classList.add("hidden");
};

/**
 * Close attendee row action menus.
 * @param {Document|Element} [root=document] Query root.
 * @param {HTMLDetailsElement|null} [exceptMenu=null] Menu to keep open.
 * @returns {void}
 */
const closeAttendeeRowActionMenus = (root = document, exceptMenu = null) => {
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
  root.querySelector?.(attendeeActionsDropdownSelector)?.classList.toggle("hidden");
};

/**
 * Apply trigger data to the refund review modal.
 * @param {HTMLElement} triggerButton Refund review trigger button.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const populateRefundReviewModal = (triggerButton, root = document) => {
  const { modal, nameField, ticketField, amountField, approveButton, rejectButton } =
    getRefundReviewControls(root);

  if (!modal) {
    return;
  }

  const status = (triggerButton.dataset.refundStatus || "pending").trim();

  if (nameField) {
    nameField.textContent = triggerButton.dataset.refundAttendeeName || "-";
  }

  if (ticketField) {
    ticketField.textContent = triggerButton.dataset.refundTicketTitle || "-";
  }

  if (amountField) {
    amountField.textContent = triggerButton.dataset.refundAmount || "-";
  }

  if (approveButton) {
    approveButton.classList.remove("hidden");
    setRefundActionLabel(
      approveButton,
      status === "approving" ? "Retry refund finalization" : "Approve refund",
    );
    if (triggerButton.dataset.refundApproveUrl) {
      approveButton.setAttribute("hx-put", triggerButton.dataset.refundApproveUrl);
    } else {
      approveButton.removeAttribute("hx-put");
    }
    processRefundActionButton(approveButton);
  }

  if (!rejectButton) {
    return;
  }

  if (status === "approving") {
    rejectButton.classList.add("hidden");
    rejectButton.removeAttribute("hx-put");
    processRefundActionButton(rejectButton);
    return;
  }

  rejectButton.classList.remove("hidden");
  if (triggerButton.dataset.refundRejectUrl) {
    rejectButton.setAttribute("hx-put", triggerButton.dataset.refundRejectUrl);
  } else {
    rejectButton.removeAttribute("hx-put");
  }
  processRefundActionButton(rejectButton);
};

// Set up the attendee modal with its dynamic endpoint and success copy.
const initializeAttendeeNotification = (root) => {
  createNotificationModal({
    modalId,
    formId,
    dataKey,
    openButtonId: "open-attendee-notification-modal",
    closeButtonId: "close-attendee-notification-modal",
    cancelButtonId: "cancel-attendee-notification",
    overlayId: "overlay-attendee-notification-modal",
    successMessage: "Email sent successfully to all event attendees!",
    root,
    // Apply the event-specific endpoint before the modal opens.
    updateEndpoint: ({ form, openButton }) => {
      if (!form) {
        return;
      }

      const eventId = openButton?.getAttribute("data-event-id") || "";
      if (eventId) {
        form.setAttribute("hx-post", `/dashboard/group/notifications/${eventId}`);
      } else {
        form.removeAttribute("hx-post");
      }
    },
  });
};

/**
 * Initialize the attendee actions dropdown.
 * @param {Document|Element} [root=document] Query root.
 */
const initializeAttendeeActionsMenu = (root = document) => {
  if (!(root instanceof Element) || root.dataset.attendeeActionsMenuReady === "true") {
    return;
  }

  root.dataset.attendeeActionsMenuReady = "true";

  root.addEventListener("click", (event) => {
    const target = event.target instanceof Element ? event.target : null;

    const rowSummary = target?.closest(`${attendeeRowActionsMenuSelector} summary`);
    const rowMenu = rowSummary?.closest(attendeeRowActionsMenuSelector);
    if (rowMenu instanceof HTMLDetailsElement && root.contains(rowMenu)) {
      closeAttendeeActionsDropdown(root);
      closeAttendeeRowActionMenus(root, rowMenu);
      return;
    }

    const rowMenuItem = target?.closest(
      `${attendeeRowActionsMenuSelector} button, ${attendeeRowActionsMenuSelector} a`,
    );
    if (rowMenuItem instanceof HTMLElement && root.contains(rowMenuItem)) {
      closeAttendeeRowActionMenus(root);
      return;
    }

    const trigger = target?.closest("#attendee-actions-button");
    if (trigger instanceof HTMLElement && root.contains(trigger)) {
      event.stopPropagation();
      closeAttendeeRowActionMenus(root);
      toggleAttendeeActionsDropdown(root);
      return;
    }

    const menuItem = target?.closest(`${attendeeActionsDropdownSelector} a`);
    if (menuItem instanceof HTMLAnchorElement && root.contains(menuItem)) {
      closeAttendeeActionsDropdown(root);
      return;
    }

    if (!target?.closest(attendeeActionsDropdownSelector)) {
      closeAttendeeActionsDropdown(root);
    }

    if (!target?.closest(attendeeRowActionsMenuSelector)) {
      closeAttendeeRowActionMenus(root);
    }
  });

  document.addEventListener("click", (event) => {
    const target = event.target instanceof Element ? event.target : null;
    if (target && !root.contains(target)) {
      closeAttendeeActionsDropdown(root);
      closeAttendeeRowActionMenus(root);
    }
  });

  root.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      const openRowMenu = root.querySelector(`${attendeeRowActionsMenuSelector}[open]`);
      const rowSummary = openRowMenu?.querySelector("summary");
      closeAttendeeActionsDropdown(root);
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
 * Initialize check-in toggle checkboxes with optimistic UI updates.
 * @param {Document|Element} [root=document] Query root.
 */
const initCheckInToggles = (root = document) => {
  root.querySelectorAll(".check-in-toggle").forEach((checkbox) => {
    if (checkbox.dataset.checkInReady === "true") {
      return;
    }

    checkbox.dataset.checkInReady = "true";
    checkbox.addEventListener("change", async () => {
      const url = checkbox.dataset.url;
      const label = checkbox.closest("label");

      // Optimistic update: disable and show as checked
      checkbox.disabled = true;
      if (label) {
        label.classList.remove("cursor-pointer");
        label.classList.add("cursor-not-allowed");
      }

      try {
        const response = await ocgFetch(url, {
          credentials: "same-origin",
          method: "POST",
        });
        if (!response.ok) {
          throw new Error("Check-in failed");
        }
      } catch {
        // Revert on error
        checkbox.checked = false;
        checkbox.disabled = false;
        if (label) {
          label.classList.add("cursor-pointer");
          label.classList.remove("cursor-not-allowed");
        }
        showErrorAlert("Failed to check in attendee. Please try again.");
      }
    });
  });
};

/**
 * Initialize refund review modal controls for attendee purchases.
 * @param {Document|Element} [root=document] Query root.
 */
const initializeRefundReviewModal = (root = document) => {
  if (!(root instanceof Element) || root.dataset.attendeeRefundReviewReady === "true") {
    return;
  }

  root.dataset.attendeeRefundReviewReady = "true";

  root.addEventListener("click", (event) => {
    const target = event.target instanceof Element ? event.target : null;
    const refundTrigger = target?.closest("[data-refund-review-trigger]");
    if (refundTrigger instanceof HTMLElement && root.contains(refundTrigger)) {
      event.stopPropagation();
      populateRefundReviewModal(refundTrigger, root);
      openRefundModal(root);
      return;
    }

    if (
      target?.closest(
        "#close-attendee-refund-modal, #cancel-attendee-refund-modal, #overlay-attendee-refund-modal",
      )
    ) {
      event.stopPropagation();
      closeRefundModal(root);
    }
  });

  root.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      closeRefundModal(root);
    }
  });

  root.addEventListener("htmx:afterRequest", (event) => {
    const requestTarget = event.target;
    if (
      !(requestTarget instanceof HTMLElement) ||
      ![refundApproveButtonId, refundRejectButtonId].includes(requestTarget.id)
    ) {
      return;
    }

    if (isSuccessfulXHRStatus(event.detail?.xhr?.status)) {
      closeRefundModal(root);
    }
  });
};

/**
 * Initialize attendee answer review modal controls.
 * @param {Document|Element} [root=document] Query root.
 */
const initializeAnswersModal = (root = document) => {
  if (!(root instanceof Element) || root.dataset.attendeeAnswersReady === "true") {
    return;
  }

  root.dataset.attendeeAnswersReady = "true";

  root.addEventListener("click", (event) => {
    const target = event.target instanceof Element ? event.target : null;
    const answersTrigger = target?.closest("[data-attendee-answers-open]");
    if (answersTrigger instanceof HTMLElement && root.contains(answersTrigger)) {
      event.stopPropagation();
      populateAnswersModal(answersTrigger, root);
      openAnswersModal(root);
      return;
    }

    if (
      target?.closest(
        "#close-attendee-answers-modal, #cancel-attendee-answers-modal, #overlay-attendee-answers-modal",
      )
    ) {
      event.stopPropagation();
      closeAnswersModal(root);
    }
  });

  root.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      closeAnswersModal(root);
    }
  });
};

/**
 * Initialize attendee invitation modal controls and response handling.
 * @param {Document|Element} [root=document] Query root.
 */
const initializeInvitationModal = (root = document) => {
  if (!(root instanceof Element) || root.dataset.attendeeInvitationReady === "true") {
    return;
  }

  root.dataset.attendeeInvitationReady = "true";

  root.addEventListener("click", (event) => {
    const target = event.target instanceof Element ? event.target : null;
    if (target?.closest("#open-attendee-invitation-modal")) {
      event.stopPropagation();
      resetInvitationForm(root);
      toggleModalVisibility(invitationModalId);
      getInvitationSearchField(root)?.focusInput?.();
      return;
    }

    const clearUserButton = target?.closest("[data-attendee-invitation-clear-user]");
    if (clearUserButton instanceof HTMLElement && root.contains(clearUserButton)) {
      event.preventDefault();
      clearInvitationSelectedUser(root);
      return;
    }

    if (
      target?.closest(
        "#close-attendee-invitation-modal, #cancel-attendee-invitation, #overlay-attendee-invitation-modal",
      )
    ) {
      event.stopPropagation();
      closeInvitationModal(root);
    }
  });

  root.addEventListener("user-selected", (event) => {
    const user = event.detail?.user;
    const input = getElementById(root, "attendee-invitation-user-id");
    const emailInput = getElementById(root, "attendee-invitation-email");
    const selected = getElementById(root, "attendee-invitation-selected-user");
    if (!user || !input) return;

    input.value = user.user_id || "";
    if (emailInput) emailInput.value = "";
    setInvitationSubmissionField(root, "user");
    if (selected) renderInvitationSelectedUser(root, user);
    updateInvitationSubmitState(root);
  });

  root.addEventListener("user-search-query-changed", (event) => {
    const target = event.target;
    if (target instanceof Element && target.matches("user-search-field[data-attendee-invitation-search]")) {
      updateInvitationQuery(root, event.detail?.query || "");
    }
  });

  root.addEventListener("email-action-selected", (event) => {
    const target = event.target;
    if (target instanceof Element && target.matches("user-search-field[data-attendee-invitation-search]")) {
      selectInvitationEmail(root, event.detail?.email || "");
    }
  });

  root.addEventListener("input", (event) => {
    const target = event.target;
    const searchField =
      target instanceof HTMLInputElement
        ? target.closest("user-search-field[data-attendee-invitation-search]")
        : null;

    if (searchField) {
      updateInvitationQuery(root, target.value);
    }
  });

  root.addEventListener("htmx:afterRequest", (event) => {
    const requestTarget = event.target;
    if (!(requestTarget instanceof HTMLFormElement) || requestTarget.id !== "attendee-invitation-form") {
      return;
    }

    const ok = handleHtmxResponse({
      xhr: event.detail?.xhr,
      successMessage: "Invitation sent.",
      errorMessage: "Something went wrong sending this invitation. Please try again later.",
    });
    if (ok) {
      closeInvitationModal(root);
      resetInvitationForm(root);
    }
  });

  root.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      closeInvitationModal(root);
    }
  });
};

const initializeAttendeesFeatures = (root = document) => {
  const attendeesRoot = resolveAttendeesRoot(root);
  if (!attendeesRoot) {
    return;
  }

  initializeAttendeeActionsMenu(attendeesRoot);
  initializeAnswersModal(attendeesRoot);
  initializeInvitationModal(attendeesRoot);
  initializeAttendeeNotification(attendeesRoot);
  initializeQrCodeModal(attendeesRoot);
  initializeRefundReviewModal(attendeesRoot);
  initCheckInToggles(attendeesRoot);
};

initializeAttendeesFeatures();

document.addEventListener("htmx:load", (event) => {
  initializeAttendeesFeatures(event.target || document);
});

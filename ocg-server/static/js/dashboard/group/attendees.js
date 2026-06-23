import { initializeQrCodeModal } from "/static/js/dashboard/group/qr-code/modal.js";
import "/static/js/common/users/user-search-field.js";
import { handleHtmxResponse, showErrorAlert } from "/static/js/common/alerts.js";
import {
  computeUserInitials,
  isSuccessfulXHRStatus,
  toggleModalVisibility,
} from "/static/js/common/common.js";
import {
  closestElement,
  closestElementWithinRoot,
  getElementById,
  initializeOnReadyAndHtmxLoad,
  isElementHidden,
  markDatasetReady,
  setElementHidden,
} from "/static/js/common/dom.js";
import { ocgFetch } from "/static/js/common/fetch.js";
import { isEscapeEvent } from "/static/js/common/keyboard.js";
import { readTrustedHtml, setTrustedHtml } from "/static/js/common/trusted-html.js";

const modalId = "attendee-notification-modal";
const formId = "attendee-notification-form";
const dataKey = "attendeeNotificationReady";
const defaultNotificationErrorMessage =
  "Something went wrong while trying to send the email. Please try again later.";
const refundModalId = "attendee-refund-modal";
const refundApproveButtonId = "attendee-refund-approve";
const refundRejectButtonId = "attendee-refund-reject";
const answersModalId = "attendee-answers-modal";
const attendeesRootSelector = "#attendees-content";
const attendeeActionsDropdownSelector = "[data-attendee-actions-dropdown]";
const attendeeEmailActionsDropdownSelector = "[data-attendee-email-actions-dropdown]";
const attendeeRowActionsMenuSelector = "[data-attendee-row-actions-menu]";
const invitationModalId = "attendee-invitation-modal";
const invitationEmailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const attendeeEmailSelectionState = {
  active: false,
  eventId: "",
  selectedRecipients: new Map(),
};

const resolveAttendeesRoot = (root = document) => {
  if (root instanceof Element && root.matches(attendeesRootSelector)) {
    return root;
  }

  if (root instanceof Element) {
    return root.closest(attendeesRootSelector) || getElementById(root, "attendees-content") || root;
  }

  return getElementById(root, "attendees-content") || root.body || root;
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
 * Set a scoped modal visible or hidden only when its current state differs.
 * @param {Document|Element} root Query root.
 * @param {string} targetModalId Modal element id.
 * @param {boolean} visible Whether the modal should be visible.
 * @returns {void}
 */
const setScopedModalVisibility = (root, targetModalId, visible) => {
  const modal = getElementById(root, targetModalId);
  if (!modal) return;

  const isHidden = isElementHidden(modal);
  if ((visible && isHidden) || (!visible && !isHidden)) {
    toggleModalVisibility(targetModalId);
  }
};

/**
 * Closes a scoped modal when an event target matches its dismiss controls.
 * @param {Event} event Event to inspect.
 * @param {Document|Element} root Query root.
 * @param {string} closeSelector Close, cancel, and overlay selector.
 * @param {Function} closeModal Modal close callback.
 * @returns {boolean} True when the event closed the modal.
 */
const closeScopedModalFromEvent = (event, root, closeSelector, closeModal) => {
  if (!closestElementWithinRoot(event.target, closeSelector, root)) {
    return false;
  }

  event.stopPropagation();
  closeModal(root);
  return true;
};

/**
 * Binds Escape handling for a scoped modal.
 * @param {Document|Element} root Query root.
 * @param {Function} closeModal Modal close callback.
 * @returns {void}
 */
const bindScopedModalEscape = (root, closeModal) => {
  root.addEventListener("keydown", (event) => {
    if (isEscapeEvent(event)) {
      closeModal(root);
    }
  });
};

/**
 * Show the refund review modal if it is currently hidden.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const openRefundModal = (root = document) => {
  setScopedModalVisibility(root, refundModalId, true);
};

/**
 * Hide the refund review modal if it is currently visible.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const closeRefundModal = (root = document) => {
  setScopedModalVisibility(root, refundModalId, false);
};

/**
 * Hide the attendee answers modal if it is currently visible.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const closeAnswersModal = (root = document) => {
  setScopedModalVisibility(root, answersModalId, false);
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
    setTrustedHtml(content, readTrustedHtml(source));
  }
};

/**
 * Show the attendee answers modal if it is currently hidden.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const openAnswersModal = (root = document) => {
  setScopedModalVisibility(root, answersModalId, true);
};

/**
 * Hide the attendee invitation modal if it is currently visible.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const closeInvitationModal = (root = document) => {
  setScopedModalVisibility(root, invitationModalId, false);
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
 * Resolve the attendee invitation controls from the current modal.
 * @param {Document|Element} root Query root.
 * @returns {Object} Invitation controls.
 */
const getInvitationControls = (root) => ({
  form: getElementById(root, "attendee-invitation-form"),
  submit: getElementById(root, "submit-attendee-invitation"),
  userInput: getElementById(root, "attendee-invitation-user-id"),
  emailInput: getElementById(root, "attendee-invitation-email"),
  selectedUser: getElementById(root, "attendee-invitation-selected-user"),
});

/**
 * Set which invitation field should be submitted.
 * @param {Document|Element} root Query root.
 * @param {"user"|"email"|""} field Active submission field.
 * @returns {void}
 */
const setInvitationSubmissionField = (root, field) => {
  const { userInput, emailInput } = getInvitationControls(root);

  if (userInput) userInput.disabled = field !== "user";
  if (emailInput) emailInput.disabled = field !== "email";
};

/**
 * Clear attendee invitation hidden fields, selected display, and search value.
 * @param {Document|Element} root Query root.
 * @returns {void}
 */
const clearInvitationState = (root) => {
  const { userInput, emailInput, selectedUser } = getInvitationControls(root);
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
 * Clear the selected invitation user display.
 * @param {Document|Element} root Query root.
 * @returns {void}
 */
const clearInvitationSelectedUser = (root) => {
  clearInvitationState(root);
};

/**
 * Reset the attendee invitation form to its empty state.
 * @param {Document|Element} root Query root.
 * @returns {void}
 */
const resetInvitationForm = (root) => {
  clearInvitationState(root);
};

/**
 * Render the selected invitation chip with the shared user/email style.
 * @param {Document|Element} root Query root.
 * @param {Object} config Chip render configuration.
 * @param {HTMLElement} config.leadingElement Leading avatar or icon element.
 * @param {string} config.labelText Chip label text.
 * @param {string} config.removeTitle Remove button title.
 * @returns {void}
 */
const renderInvitationSelectedChip = (root, { leadingElement, labelText, removeTitle }) => {
  const { selectedUser } = getInvitationControls(root);
  if (!selectedUser) return;

  const pill = document.createElement("div");
  pill.className = "inline-flex items-center gap-2 bg-stone-100 rounded-full ps-1 pe-1 py-1";

  const label = document.createElement("span");
  label.className = "text-sm text-stone-700 pe-2";
  label.textContent = labelText;

  const removeButton = document.createElement("button");
  removeButton.type = "button";
  removeButton.className = "p-1 hover:bg-stone-200 rounded-full transition-colors";
  removeButton.title = removeTitle;
  removeButton.setAttribute("data-attendee-invitation-clear-user", "");

  const removeIcon = document.createElement("div");
  removeIcon.className = "svg-icon size-3 icon-close bg-stone-600";

  removeButton.append(removeIcon);
  pill.append(leadingElement, label, removeButton);
  selectedUser.replaceChildren(pill);
};

/**
 * Render the selected invitation user with the shared user chip style.
 * @param {Document|Element} root Query root.
 * @param {Object} user Selected user.
 * @returns {void}
 */
const renderInvitationSelectedUser = (root, user) => {
  const avatar = document.createElement("logo-image");
  avatar.setAttribute("image-url", user.photo_url || "");
  avatar.setAttribute("placeholder", computeUserInitials(user.name, user.username, 2));
  avatar.setAttribute("size", "size-[24px]");
  avatar.setAttribute("font-size", "text-xs");
  avatar.setAttribute("hide-border", "true");

  renderInvitationSelectedChip(root, {
    leadingElement: avatar,
    labelText: user.name || user.username,
    removeTitle: "Remove user",
  });
};

/**
 * Render the selected invitation email with the shared chip style.
 * @param {Document|Element} root Query root.
 * @param {string} email Selected email.
 * @returns {void}
 */
const renderInvitationSelectedEmail = (root, email) => {
  const iconBox = document.createElement("span");
  iconBox.className =
    "inline-flex size-[24px] shrink-0 items-center justify-center rounded-full bg-stone-200";

  const icon = document.createElement("div");
  icon.className = "svg-icon size-3.5 icon-email bg-stone-600";

  iconBox.append(icon);
  renderInvitationSelectedChip(root, {
    leadingElement: iconBox,
    labelText: email,
    removeTitle: "Remove email",
  });
};

/**
 * Enable the invitation submit button when a user or valid email is present.
 * @param {Document|Element} root Query root.
 * @returns {void}
 */
const updateInvitationSubmitState = (root) => {
  const { form, submit, userInput, emailInput } = getInvitationControls(root);
  if (!form || !submit) return;

  const userId = userInput?.value || "";
  const email = emailInput?.value.trim() || "";
  submit.disabled = userId === "" && !isValidInvitationEmail(email);
};

/**
 * Update hidden invitation fields from the current search query.
 * @param {Document|Element} root Query root.
 * @param {string} query Search query.
 * @returns {void}
 */
const updateInvitationQuery = (root, query) => {
  const { userInput, emailInput, selectedUser } = getInvitationControls(root);
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
  const { userInput, emailInput } = getInvitationControls(root);
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
  setElementHidden(root.querySelector?.(attendeeActionsDropdownSelector), true);
};

/**
 * Close the attendee email actions dropdown.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const closeAttendeeEmailActionsDropdown = (root = document) => {
  setElementHidden(root.querySelector?.(attendeeEmailActionsDropdownSelector), true);
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
  const dropdown = root.querySelector?.(attendeeActionsDropdownSelector);
  setElementHidden(dropdown, !isElementHidden(dropdown));
};

/**
 * Toggle the attendee email actions dropdown.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const toggleAttendeeEmailActionsDropdown = (root = document) => {
  const dropdown = root.querySelector?.(attendeeEmailActionsDropdownSelector);
  setElementHidden(dropdown, !isElementHidden(dropdown));
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
    setElementHidden(approveButton, false);
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
    setElementHidden(rejectButton, true);
    rejectButton.removeAttribute("hx-put");
    processRefundActionButton(rejectButton);
    return;
  }

  setElementHidden(rejectButton, false);
  if (triggerButton.dataset.refundRejectUrl) {
    rejectButton.setAttribute("hx-put", triggerButton.dataset.refundRejectUrl);
  } else {
    rejectButton.removeAttribute("hx-put");
  }
  processRefundActionButton(rejectButton);
};

/**
 * Resolve attendee notification modal controls from the current page root.
 * @param {Document|Element} root Query root.
 * @returns {Object} Notification controls.
 */
const getAttendeeNotificationControls = (root) => ({
  form: getElementById(root, formId),
  modal: getElementById(root, modalId),
  recipientScope: getElementById(root, "attendee-notification-recipient-scope"),
  recipientSummary: getElementById(root, "attendee-notification-recipient-summary"),
  selectedFields: getElementById(root, "attendee-notification-selected-fields"),
  submit: getElementById(root, "submit-attendee-notification"),
});

/**
 * Resolve attendee email selection controls from the current page root.
 * @param {Document|Element} root Query root.
 * @returns {Object} Email selection controls.
 */
const getAttendeeEmailSelectionControls = (root) => ({
  bar: root.querySelector?.("[data-attendee-email-selection-bar]"),
  cancel: root.querySelector?.("[data-attendee-email-selection-cancel]"),
  checkboxes: root.querySelectorAll?.("[data-attendee-email-selection-checkbox]") || [],
  clear: root.querySelector?.("[data-attendee-email-selection-clear]"),
  columns: root.querySelectorAll?.("[data-attendee-email-selection-column]") || [],
  count: root.querySelector?.("[data-attendee-email-selection-count]"),
  send: root.querySelector?.("[data-attendee-email-selection-send]"),
  start: root.querySelector?.("[data-attendee-email-selection-start]"),
});

/**
 * Convert recipient data attributes into a selected recipient object.
 * @param {HTMLElement} element Element carrying recipient data.
 * @returns {Object|null} Recipient object.
 */
const readRecipientFromElement = (element) => {
  const id = element.dataset.recipientId || element.value || "";
  if (!id) {
    return null;
  }

  return {
    email: element.dataset.recipientEmail || "",
    id,
    name: element.dataset.recipientName || "",
    username: element.dataset.recipientUsername || "",
  };
};

/**
 * Return selected recipients in submission order.
 * @returns {Array<Object>} Selected recipients.
 */
const getSelectedEmailRecipients = () => Array.from(attendeeEmailSelectionState.selectedRecipients.values());

/**
 * Read one submitted HTMX parameter from FormData, URLSearchParams, or a plain object.
 * @param {FormData|URLSearchParams|Object|null|undefined} parameters Submitted parameters.
 * @param {string} name Parameter name.
 * @returns {string} Submitted parameter value.
 */
const readSubmittedParameter = (parameters, name) => {
  if (!parameters) {
    return "";
  }

  if (typeof parameters.get === "function") {
    return parameters.get(name) || "";
  }

  return parameters[name] || "";
};

/**
 * Build hidden recipient fields for selected notification sends.
 * @param {Document|Element} root Query root.
 * @param {Array<Object>} recipients Selected recipients.
 * @returns {void}
 */
const renderNotificationRecipientFields = (root, recipients) => {
  const { selectedFields } = getAttendeeNotificationControls(root);
  if (!selectedFields) return;

  const hiddenInputs = recipients.map((recipient, index) => {
    const input = document.createElement("input");
    input.type = "hidden";
    input.name = `recipient_user_ids[${index}]`;
    input.value = recipient.id;
    return input;
  });
  selectedFields.replaceChildren(...hiddenInputs);
};

/**
 * Format the recipient count for display.
 * @param {number} count Recipient count.
 * @param {string} singular Singular label.
 * @param {string} plural Plural label.
 * @returns {string} Formatted count.
 */
const formatRecipientCount = (count, singular, plural) => `${count} ${count === 1 ? singular : plural}`;

/**
 * Configure the compose modal recipient scope, copy, and hidden fields.
 * @param {Document|Element} root Query root.
 * @param {Object} config Recipient configuration.
 * @param {"all"|"selected"} config.scope Recipient scope.
 * @param {number} [config.allRecipientTotal=0] Event-wide eligible recipient count.
 * @param {Array<Object>} [config.recipients=[]] Selected recipients.
 * @returns {void}
 */
const setNotificationRecipients = (root, { scope, allRecipientTotal = 0, recipients = [] }) => {
  const { recipientScope, recipientSummary, submit } = getAttendeeNotificationControls(root);
  const normalizedScope = scope === "selected" ? "selected" : "all";

  if (recipientScope) {
    recipientScope.value = normalizedScope;
  }
  renderNotificationRecipientFields(root, normalizedScope === "selected" ? recipients : []);

  if (recipientSummary) {
    if (normalizedScope === "selected") {
      recipientSummary.textContent = `This email will be sent to ${formatRecipientCount(
        recipients.length,
        "selected attendee",
        "selected attendees",
      )}.`;
    } else {
      recipientSummary.textContent = `This email will be sent to ${formatRecipientCount(
        allRecipientTotal,
        "eligible attendee",
        "eligible attendees",
      )}.`;
    }
  }

  if (submit) {
    const baseDisabled = submit.dataset.notificationBaseDisabled?.trim() === "true";
    submit.disabled = baseDisabled || (normalizedScope === "selected" && recipients.length === 0);
  }
};

/**
 * Update the form endpoint for the selected event.
 * @param {Document|Element} root Query root.
 * @param {string} eventId Event id.
 * @returns {void}
 */
const setNotificationEndpoint = (root, eventId) => {
  const { form } = getAttendeeNotificationControls(root);
  if (!form) return;

  if (eventId) {
    form.setAttribute("hx-post", `/dashboard/group/notifications/${eventId}`);
  } else {
    form.removeAttribute("hx-post");
  }
};

/**
 * Reset attendee notification form fields to the all-recipient default.
 * @param {Document|Element} root Query root.
 * @returns {void}
 */
const resetNotificationForm = (root) => {
  const { form, recipientSummary, submit } = getAttendeeNotificationControls(root);
  const allRecipientTotal = Number(recipientSummary?.dataset.allRecipientTotal || 0);

  form?.reset();
  setNotificationRecipients(root, {
    allRecipientTotal,
    recipients: [],
    scope: "all",
  });
  if (submit) {
    submit.dataset.notificationBaseDisabled = submit.disabled ? "true" : "false";
  }
};

/**
 * Hide the attendee notification modal if visible.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const closeNotificationModal = (root = document) => {
  setScopedModalVisibility(root, modalId, false);
};

/**
 * Open the attendee notification modal for all or selected recipients.
 * @param {Document|Element} root Query root.
 * @param {Object} config Open configuration.
 * @param {number} [config.allRecipientTotal=0] Event-wide eligible recipient count.
 * @param {string} config.eventId Event id.
 * @param {Array<Object>} [config.recipients=[]] Selected recipients.
 * @param {"all"|"selected"} config.scope Recipient scope.
 * @returns {void}
 */
const openNotificationModal = (root, { allRecipientTotal = 0, eventId, recipients = [], scope }) => {
  resetNotificationForm(root);
  setNotificationEndpoint(root, eventId || "");
  setNotificationRecipients(root, {
    allRecipientTotal,
    recipients,
    scope,
  });
  setScopedModalVisibility(root, modalId, true);
};

/**
 * Synchronize the current table checkboxes with selected recipients.
 * @param {Document|Element} root Query root.
 * @returns {void}
 */
const syncEmailSelectionCheckboxes = (root) => {
  const { checkboxes } = getAttendeeEmailSelectionControls(root);
  checkboxes.forEach((checkbox) => {
    checkbox.checked = attendeeEmailSelectionState.selectedRecipients.has(checkbox.value);
  });
};

/**
 * Render email selection mode into the current attendees table.
 * @param {Document|Element} root Query root.
 * @returns {void}
 */
const renderEmailSelectionState = (root) => {
  const { bar, checkboxes, columns, count, send, start } = getAttendeeEmailSelectionControls(root);
  const currentEventId = start?.dataset.eventId || "";

  if (
    attendeeEmailSelectionState.eventId &&
    currentEventId &&
    attendeeEmailSelectionState.eventId !== currentEventId
  ) {
    attendeeEmailSelectionState.active = false;
    attendeeEmailSelectionState.eventId = "";
    attendeeEmailSelectionState.selectedRecipients.clear();
  }

  const active = attendeeEmailSelectionState.active;
  setElementHidden(bar, !active);
  columns.forEach((column) => setElementHidden(column, !active));
  syncEmailSelectionCheckboxes(root);

  const selectedCount = attendeeEmailSelectionState.selectedRecipients.size;
  if (count) {
    count.textContent = String(selectedCount);
  }
  if (send) {
    send.disabled = !active || selectedCount === 0;
  }
  if (!active) {
    checkboxes.forEach((checkbox) => {
      checkbox.checked = false;
    });
  }
};

/**
 * Enable or disable email selection mode.
 * @param {Document|Element} root Query root.
 * @param {boolean} active Whether selection mode is active.
 * @param {string} [eventId=""] Event id.
 * @returns {void}
 */
const setEmailSelectionMode = (root, active, eventId = "") => {
  if (eventId && attendeeEmailSelectionState.eventId && attendeeEmailSelectionState.eventId !== eventId) {
    attendeeEmailSelectionState.selectedRecipients.clear();
  }
  attendeeEmailSelectionState.active = active;
  attendeeEmailSelectionState.eventId = active ? eventId || attendeeEmailSelectionState.eventId : "";
  if (!active) {
    attendeeEmailSelectionState.selectedRecipients.clear();
  }
  renderEmailSelectionState(root);
};

/**
 * Clear selected email recipients while keeping selection mode active.
 * @param {Document|Element} root Query root.
 * @returns {void}
 */
const clearEmailSelection = (root) => {
  attendeeEmailSelectionState.selectedRecipients.clear();
  renderEmailSelectionState(root);
};

/**
 * Add or remove one attendee from the email selection.
 * @param {Document|Element} root Query root.
 * @param {HTMLInputElement} checkbox Selection checkbox.
 * @returns {void}
 */
const toggleEmailSelectionRecipient = (root, checkbox) => {
  const recipient = readRecipientFromElement(checkbox);
  if (!recipient) return;

  if (checkbox.checked) {
    attendeeEmailSelectionState.selectedRecipients.set(recipient.id, recipient);
  } else {
    attendeeEmailSelectionState.selectedRecipients.delete(recipient.id);
  }
  renderEmailSelectionState(root);
};

/**
 * Start table-integrated email selection mode.
 * @param {Document|Element} root Query root.
 * @param {HTMLElement} trigger Start trigger.
 * @returns {void}
 */
const startEmailSelection = (root, trigger) => {
  setEmailSelectionMode(root, true, trigger.dataset.eventId || "");
  const firstCheckbox = root.querySelector("[data-attendee-email-selection-checkbox]");
  if (firstCheckbox instanceof HTMLElement) {
    firstCheckbox.focus();
  }
};

/**
 * Open the compose modal using the current table selection.
 * @param {Document|Element} root Query root.
 * @returns {void}
 */
const openNotificationFromSelection = (root) => {
  const recipients = getSelectedEmailRecipients();
  if (recipients.length === 0) {
    return;
  }

  openNotificationModal(root, {
    eventId: attendeeEmailSelectionState.eventId,
    recipients,
    scope: "selected",
  });
};

/**
 * Initialize attendee notification modal controls and response handling.
 * @param {Document|Element} [root=document] Query root.
 */
const initializeAttendeeNotification = (root = document) => {
  if (!(root instanceof Element) || !markDatasetReady(root, dataKey)) {
    return;
  }

  const { submit } = getAttendeeNotificationControls(root);
  if (submit) {
    submit.dataset.notificationBaseDisabled = submit.disabled ? "true" : "false";
  }

  root.addEventListener("click", (event) => {
    const openTrigger = closestElementWithinRoot(event.target, "[data-attendee-notification-open]", root);
    if (openTrigger instanceof HTMLElement && !openTrigger.hasAttribute("disabled")) {
      event.stopPropagation();
      closeAttendeeActionsDropdown(root);
      closeAttendeeEmailActionsDropdown(root);
      closeAttendeeRowActionMenus(root);
      const scope = openTrigger.dataset.notificationScope === "selected" ? "selected" : "all";
      const recipient = scope === "selected" ? readRecipientFromElement(openTrigger) : null;
      openNotificationModal(root, {
        allRecipientTotal: Number(openTrigger.dataset.notificationRecipientTotal || 0),
        eventId: openTrigger.dataset.eventId || "",
        recipients: recipient ? [recipient] : [],
        scope,
      });
      return;
    }

    closeScopedModalFromEvent(
      event,
      root,
      "#close-attendee-notification-modal, #cancel-attendee-notification, #overlay-attendee-notification-modal",
      closeNotificationModal,
    );
  });

  root.addEventListener("htmx:afterRequest", (event) => {
    const requestTarget = event.target;
    if (!(requestTarget instanceof HTMLFormElement) || requestTarget.id !== formId) {
      return;
    }

    const submittedRecipientScope = requestTarget.elements.namedItem("recipient_scope");
    const submittedScope =
      readSubmittedParameter(event.detail?.requestConfig?.parameters, "recipient_scope") ||
      readSubmittedParameter(event.detail?.parameters, "recipient_scope") ||
      (submittedRecipientScope instanceof HTMLInputElement ? submittedRecipientScope.value : "");
    const scope = submittedScope === "selected" ? "selected" : "all";
    const ok = handleHtmxResponse({
      xhr: event.detail?.xhr,
      successMessage:
        scope === "selected"
          ? "Email sent successfully to selected attendees!"
          : "Email sent successfully to all event attendees!",
      errorMessage: event.detail?.xhr?.responseText || defaultNotificationErrorMessage,
    });
    if (ok) {
      resetNotificationForm(root);
      closeNotificationModal(root);
      setEmailSelectionMode(root, false);
    }
  });

  bindScopedModalEscape(root, closeNotificationModal);
  renderEmailSelectionState(root);
};

/**
 * Initialize table-integrated attendee email selection controls.
 * @param {Document|Element} [root=document] Query root.
 */
const initializeAttendeeEmailSelection = (root = document) => {
  if (!(root instanceof Element)) {
    return;
  }

  if (!markDatasetReady(root, "attendeeEmailSelectionReady")) {
    renderEmailSelectionState(root);
    return;
  }

  root.addEventListener("click", (event) => {
    const startTrigger = closestElementWithinRoot(
      event.target,
      "[data-attendee-email-selection-start]",
      root,
    );
    if (startTrigger instanceof HTMLElement) {
      event.stopPropagation();
      closeAttendeeEmailActionsDropdown(root);
      closeAttendeeActionsDropdown(root);
      closeAttendeeRowActionMenus(root);
      startEmailSelection(root, startTrigger);
      return;
    }

    if (closestElementWithinRoot(event.target, "[data-attendee-email-selection-clear]", root)) {
      event.preventDefault();
      clearEmailSelection(root);
      return;
    }

    if (closestElementWithinRoot(event.target, "[data-attendee-email-selection-cancel]", root)) {
      event.preventDefault();
      setEmailSelectionMode(root, false);
      getElementById(root, "attendee-email-actions-button")?.focus();
      return;
    }

    if (closestElementWithinRoot(event.target, "[data-attendee-email-selection-send]", root)) {
      event.preventDefault();
      openNotificationFromSelection(root);
    }
  });

  root.addEventListener("change", (event) => {
    const target = event.target;
    if (target instanceof HTMLInputElement && target.matches("[data-attendee-email-selection-checkbox]")) {
      toggleEmailSelectionRecipient(root, target);
    }
  });

  renderEmailSelectionState(root);
};

/**
 * Initialize the attendee actions dropdown.
 * @param {Document|Element} [root=document] Query root.
 */
const initializeAttendeeActionsMenu = (root = document) => {
  if (!(root instanceof Element) || !markDatasetReady(root, "attendeeActionsMenuReady")) {
    return;
  }

  root.addEventListener("click", (event) => {
    const rowSummary = closestElementWithinRoot(
      event.target,
      `${attendeeRowActionsMenuSelector} summary`,
      root,
    );
    const rowMenu = rowSummary?.closest(attendeeRowActionsMenuSelector);
    if (rowMenu instanceof HTMLDetailsElement) {
      closeAttendeeActionsDropdown(root);
      closeAttendeeEmailActionsDropdown(root);
      closeAttendeeRowActionMenus(root, rowMenu);
      return;
    }

    const rowMenuItem = closestElementWithinRoot(
      event.target,
      `${attendeeRowActionsMenuSelector} button, ${attendeeRowActionsMenuSelector} a`,
      root,
    );
    if (rowMenuItem instanceof HTMLElement) {
      closeAttendeeRowActionMenus(root);
      return;
    }

    const trigger = closestElementWithinRoot(event.target, "#attendee-actions-button", root);
    if (trigger instanceof HTMLElement) {
      event.stopPropagation();
      closeAttendeeEmailActionsDropdown(root);
      closeAttendeeRowActionMenus(root);
      toggleAttendeeActionsDropdown(root);
      return;
    }

    const emailTrigger = closestElementWithinRoot(event.target, "#attendee-email-actions-button", root);
    if (emailTrigger instanceof HTMLElement) {
      event.stopPropagation();
      closeAttendeeActionsDropdown(root);
      closeAttendeeRowActionMenus(root);
      toggleAttendeeEmailActionsDropdown(root);
      return;
    }

    const menuItem = closestElementWithinRoot(event.target, `${attendeeActionsDropdownSelector} a`, root);
    if (menuItem instanceof HTMLAnchorElement) {
      closeAttendeeActionsDropdown(root);
      return;
    }

    const emailMenuItem = closestElementWithinRoot(
      event.target,
      `${attendeeEmailActionsDropdownSelector} button`,
      root,
    );
    if (emailMenuItem instanceof HTMLButtonElement) {
      closeAttendeeEmailActionsDropdown(root);
      return;
    }

    if (!closestElementWithinRoot(event.target, attendeeActionsDropdownSelector, root)) {
      closeAttendeeActionsDropdown(root);
    }

    if (!closestElementWithinRoot(event.target, attendeeEmailActionsDropdownSelector, root)) {
      closeAttendeeEmailActionsDropdown(root);
    }

    if (!closestElementWithinRoot(event.target, attendeeRowActionsMenuSelector, root)) {
      closeAttendeeRowActionMenus(root);
    }
  });

  root.addEventListener("keydown", (event) => {
    if (isEscapeEvent(event)) {
      const openRowMenu = root.querySelector(`${attendeeRowActionsMenuSelector}[open]`);
      const rowSummary = openRowMenu?.querySelector("summary");
      closeAttendeeActionsDropdown(root);
      closeAttendeeEmailActionsDropdown(root);
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
 * Initialize document-level attendee menu cleanup.
 */
const initializeAttendeeOutsideClickListener = () => {
  if (!markDatasetReady(document.documentElement, "attendeeOutsideClickReady")) {
    return;
  }

  document.addEventListener("click", (event) => {
    const target = event.target instanceof Element ? event.target : null;
    if (!target) {
      return;
    }

    document.querySelectorAll(attendeesRootSelector).forEach((root) => {
      if (!root.contains(target)) {
        closeAttendeeActionsDropdown(root);
        closeAttendeeEmailActionsDropdown(root);
        closeAttendeeRowActionMenus(root);
      }
    });
  });
};

/**
 * Initialize check-in toggle checkboxes with optimistic UI updates.
 * @param {Document|Element} [root=document] Query root.
 */
const initCheckInToggles = (root = document) => {
  root.querySelectorAll(".check-in-toggle").forEach((checkbox) => {
    if (!markDatasetReady(checkbox, "checkInReady")) {
      return;
    }

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
  if (!(root instanceof Element) || !markDatasetReady(root, "attendeeRefundReviewReady")) {
    return;
  }

  root.addEventListener("click", (event) => {
    const refundTrigger = closestElementWithinRoot(event.target, "[data-refund-review-trigger]", root);
    if (refundTrigger instanceof HTMLElement) {
      event.stopPropagation();
      populateRefundReviewModal(refundTrigger, root);
      openRefundModal(root);
      return;
    }

    closeScopedModalFromEvent(
      event,
      root,
      "#close-attendee-refund-modal, #cancel-attendee-refund-modal, #overlay-attendee-refund-modal",
      closeRefundModal,
    );
  });

  bindScopedModalEscape(root, closeRefundModal);

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
  if (!(root instanceof Element) || !markDatasetReady(root, "attendeeAnswersReady")) {
    return;
  }

  root.addEventListener("click", (event) => {
    const answersTrigger = closestElementWithinRoot(event.target, "[data-attendee-answers-open]", root);
    if (answersTrigger instanceof HTMLElement) {
      event.stopPropagation();
      populateAnswersModal(answersTrigger, root);
      openAnswersModal(root);
      return;
    }

    closeScopedModalFromEvent(
      event,
      root,
      "#close-attendee-answers-modal, #cancel-attendee-answers-modal, #overlay-attendee-answers-modal",
      closeAnswersModal,
    );
  });

  bindScopedModalEscape(root, closeAnswersModal);
};

/**
 * Initialize attendee invitation modal controls and response handling.
 * @param {Document|Element} [root=document] Query root.
 */
const initializeInvitationModal = (root = document) => {
  if (!(root instanceof Element) || !markDatasetReady(root, "attendeeInvitationReady")) {
    return;
  }

  root.addEventListener("click", (event) => {
    if (closestElementWithinRoot(event.target, "#open-attendee-invitation-modal", root)) {
      // Opening the modal always starts from a clean search and selection state.
      event.stopPropagation();
      resetInvitationForm(root);
      setScopedModalVisibility(root, invitationModalId, true);
      getInvitationSearchField(root)?.focusInput?.();
      return;
    }

    const clearUserButton = closestElementWithinRoot(
      event.target,
      "[data-attendee-invitation-clear-user]",
      root,
    );
    if (clearUserButton instanceof HTMLElement) {
      event.preventDefault();
      clearInvitationSelectedUser(root);
      return;
    }

    closeScopedModalFromEvent(
      event,
      root,
      "#close-attendee-invitation-modal, #cancel-attendee-invitation, #overlay-attendee-invitation-modal",
      closeInvitationModal,
    );
  });

  // User search is a custom element, so selection and query changes are events.
  root.addEventListener("user-selected", (event) => {
    const user = event.detail?.user;
    const { userInput, emailInput, selectedUser } = getInvitationControls(root);
    if (!user || !userInput) return;

    userInput.value = user.user_id || "";
    if (emailInput) emailInput.value = "";
    setInvitationSubmissionField(root, "user");
    if (selectedUser) renderInvitationSelectedUser(root, user);
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
        ? closestElement(target, "user-search-field[data-attendee-invitation-search]")
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
      // The attendee list refreshes through HTMX; reset local modal state now.
      closeInvitationModal(root);
      resetInvitationForm(root);
    }
  });

  bindScopedModalEscape(root, closeInvitationModal);
};

const initializeAttendeesFeatures = (root = document) => {
  const attendeesRoot = resolveAttendeesRoot(root);
  if (!attendeesRoot) {
    return;
  }

  initializeAttendeeActionsMenu(attendeesRoot);
  initializeAttendeeEmailSelection(attendeesRoot);
  initializeAnswersModal(attendeesRoot);
  initializeInvitationModal(attendeesRoot);
  initializeAttendeeNotification(attendeesRoot);
  initializeQrCodeModal(attendeesRoot);
  initializeRefundReviewModal(attendeesRoot);
  initCheckInToggles(attendeesRoot);
  initializeAttendeeOutsideClickListener();
};

initializeOnReadyAndHtmxLoad(initializeAttendeesFeatures);

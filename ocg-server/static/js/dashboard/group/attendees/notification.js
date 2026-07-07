import { handleHtmxResponse } from "/static/js/common/alerts.js";
import {
  closestElementWithinRoot,
  getElementById,
  markDatasetReady,
  setElementHidden,
} from "/static/js/common/dom.js";
import {
  closeAttendeeActionsDropdown,
  closeAttendeeEmailActionsDropdown,
  closeAttendeeRowActionMenus,
} from "/static/js/dashboard/group/attendees/actions-menu.js";
import {
  bindScopedModalEscape,
  closeScopedModalFromEvent,
  setScopedModalVisibility,
} from "/static/js/dashboard/group/attendees/shared.js";

const modalId = "attendee-notification-modal";
const formId = "attendee-notification-form";
const dataKey = "attendeeNotificationReady";
const defaultNotificationErrorMessage =
  "Something went wrong while trying to send the email. Please try again later.";
const attendeeEmailSelectionState = {
  active: false,
  eventId: "",
  selectedRecipients: new Map(),
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
  headerSend: getElementById(root, "attendee-email-actions-button"),
  label: root.querySelector?.("[data-attendee-email-selection-label]"),
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
  const { bar, checkboxes, columns, count, headerSend, label, send, start } =
    getAttendeeEmailSelectionControls(root);
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
  if (label) {
    label.textContent = selectedCount === 1 ? "attendee selected" : "attendees selected";
  }
  if (send) {
    send.disabled = !active || selectedCount === 0;
  }
  if (headerSend) {
    if (!("emailSelectionBaseDisabled" in headerSend.dataset)) {
      headerSend.dataset.emailSelectionBaseDisabled = headerSend.disabled ? "true" : "false";
    }
    const baseDisabled = headerSend.dataset.emailSelectionBaseDisabled === "true";
    headerSend.disabled = baseDisabled || active;
    headerSend.classList.toggle("opacity-50", baseDisabled || active);
    headerSend.classList.toggle("cursor-not-allowed", baseDisabled || active);
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
export const initializeAttendeeNotification = (root = document) => {
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
export const initializeAttendeeEmailSelection = (root = document) => {
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

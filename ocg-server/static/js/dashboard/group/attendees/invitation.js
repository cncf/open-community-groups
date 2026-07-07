import { handleHtmxResponse } from "/static/js/common/alerts.js";
import {
  closestElement,
  closestElementWithinRoot,
  getElementById,
  markDatasetReady,
} from "/static/js/common/dom.js";
import "/static/js/common/media/logo-image.js";
import { computeUserInitials } from "/static/js/common/users/initials.js";
import {
  bindScopedModalEscape,
  closeScopedModalFromEvent,
  setScopedModalVisibility,
} from "/static/js/dashboard/group/attendees/shared.js";

const invitationModalId = "attendee-invitation-modal";
const invitationEmailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

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
 * Initialize attendee invitation modal controls and response handling.
 * @param {Document|Element} [root=document] Query root.
 */
export const initializeInvitationModal = (root = document) => {
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

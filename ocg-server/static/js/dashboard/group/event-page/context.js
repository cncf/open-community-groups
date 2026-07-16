import { getElementById, markDatasetReady } from "/static/js/common/dom.js";
import { collectExistingFormIds } from "/static/js/dashboard/group/page-form-state.js";
import { initializePendingChangesAlert } from "/static/js/dashboard/group/pending-changes-alert.js";

export const EVENT_PAGE_FORM_IDS = [
  "details-form",
  "date-venue-form",
  "hosts-sponsors-form",
  "sessions-form",
  "payments-form",
  "questions-form",
  "cfs-form",
];

/**
 * Resolves the page root for an event page bootstrap.
 * @param {Document|Element} root Query root.
 * @param {"add"|"update"} pageName Page marker value.
 * @returns {Document|Element} Page root or the provided root.
 */
const resolveEventPageRoot = (root, pageName) => {
  if (root instanceof Element && root.matches(`[data-event-page="${pageName}"]`)) {
    return root;
  }

  return root.querySelector?.(`[data-event-page="${pageName}"]`) || root;
};

/**
 * Initializes the shared root-scoped page context for an event bootstrap.
 * @param {Document|Element} root Query root.
 * @param {"add"|"update"} pageName Page marker value.
 * @returns {Object|null} Shared context, or null when already initialized.
 */
export const initializeEventPageContext = (root, pageName) => {
  const pageRoot = resolveEventPageRoot(root, pageName);
  if (pageRoot instanceof HTMLElement && !markDatasetReady(pageRoot, "eventPageReady")) {
    return null;
  }

  return {
    pageRoot,
    queryOne: (selector) => pageRoot.querySelector(selector),
  };
};

/**
 * Resolves the controls shared by add and update event pages.
 * @param {Document|Element} pageRoot Page root.
 * @returns {Object} Shared event page controls.
 */
export const resolveSharedEventPageControls = (pageRoot) => ({
  kindSelect: getElementById(pageRoot, "kind_id"),
  onlineEventDetails: getElementById(pageRoot, "online-event-details"),
  clearLocationButton: getElementById(pageRoot, "clear-location-fields"),
  toggleCfsEnabled: getElementById(pageRoot, "toggle_cfs_enabled"),
  cfsEnabledInput: getElementById(pageRoot, "cfs_enabled"),
  cfsStartsAtInput: getElementById(pageRoot, "cfs_starts_at"),
  cfsEndsAtInput: getElementById(pageRoot, "cfs_ends_at"),
  cfsDescriptionInput: getElementById(pageRoot, "cfs_description"),
  cfsLabelsEditor: getElementById(pageRoot, "cfs-labels-editor"),
  registrationStartsAtInput: getElementById(pageRoot, "registration_starts_at"),
  registrationEndsAtInput: getElementById(pageRoot, "registration_ends_at"),
  startsAtInput: getElementById(pageRoot, "starts_at"),
  endsAtInput: getElementById(pageRoot, "ends_at"),
});

/**
 * Builds a session date range sync function for sessions-section.
 * @param {Object} config Sync configuration.
 * @param {(selector: string) => Element|null} config.queryOne Root-scoped query helper.
 * @param {HTMLInputElement|null} config.startsAtInput Event start input.
 * @param {HTMLInputElement|null} config.endsAtInput Event end input.
 * @returns {() => void} Sync function.
 */
export const createSessionsDateRangeSync =
  ({ queryOne, startsAtInput, endsAtInput }) =>
  () => {
    const sessionsSection = queryOne("sessions-section");
    if (!sessionsSection) {
      return;
    }

    sessionsSection.eventStartsAt = startsAtInput?.value || "";
    sessionsSection.eventEndsAt = endsAtInput?.value || "";
    sessionsSection.requestUpdate?.();
  };

/**
 * Initializes the shared pending-changes alert for event pages.
 * @param {Object} config Pending-changes configuration.
 * @param {Document|Element} config.pageRoot Page root.
 * @param {string} config.confirmMessage Confirmation text shown on cancel.
 * @returns {void}
 */
export const initializeEventPagePendingChanges = ({ pageRoot, confirmMessage }) => {
  initializePendingChangesAlert({
    alertId: "pending-changes-alert",
    formIds: collectExistingFormIds(EVENT_PAGE_FORM_IDS, pageRoot),
    cancelButtonId: "cancel-button",
    confirmMessage,
    confirmText: "Leave",
  });
};

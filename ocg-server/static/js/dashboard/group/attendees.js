import "/static/js/common/actions-menu.js";
import { initializeOnReadyAndHtmxLoad } from "/static/js/common/dom.js";
import "/static/js/common/modals/user-info-modal.js";
import "/static/js/common/users/user-profile-modal-triggers.js";
import "/static/js/common/users/user-search-field.js";
import {
  initializeAttendeeActionsMenu,
  initializeAttendeeOutsideClickListener,
  closeAttendeeRowActionMenus,
} from "/static/js/dashboard/group/attendees/actions-menu.js";
import { initializeAnswersModal } from "/static/js/dashboard/group/attendees/answers.js";
import { initializeAttendeeBadgeAwards } from "/static/js/dashboard/group/attendees/badge-awards.js";
import { initCheckInToggles } from "/static/js/dashboard/group/attendees/check-in.js";
import { initializeExternalPaymentModal } from "/static/js/dashboard/group/attendees/external-payment.js";
import { initializeInvitationModal } from "/static/js/dashboard/group/attendees/invitation.js";
import {
  initializeAttendeeEmailSelection,
  initializeAttendeeNotification,
} from "/static/js/dashboard/group/attendees/notification.js";
import { initializeRefundReviewModal } from "/static/js/dashboard/group/attendees/refunds.js";
import { resolveAttendeesRoot } from "/static/js/dashboard/group/attendees/shared.js";

/**
 * Close the attendee row menu before opening its answers modal.
 * @param {HTMLElement} trigger Answers modal trigger.
 * @param {Document|Element} root Attendees page root.
 * @returns {HTMLElement} Element that should regain focus when the modal closes.
 */
const prepareAttendeeAnswersOpen = (trigger, root) => {
  const actionsMenuSummary = trigger.closest("[data-actions-menu]")?.querySelector("summary");
  closeAttendeeRowActionMenus(root);
  return actionsMenuSummary instanceof HTMLElement ? actionsMenuSummary : trigger;
};

const initializeAttendeesFeatures = (root = document) => {
  const attendeesRoot = resolveAttendeesRoot(root);
  if (!attendeesRoot) {
    return;
  }

  initializeAttendeeActionsMenu(attendeesRoot);
  initializeAttendeeBadgeAwards(attendeesRoot);
  initializeAttendeeEmailSelection(attendeesRoot);
  initializeAnswersModal(attendeesRoot, undefined, prepareAttendeeAnswersOpen);
  initializeExternalPaymentModal(attendeesRoot);
  initializeInvitationModal(attendeesRoot);
  initializeAttendeeNotification(attendeesRoot);
  initializeRefundReviewModal(attendeesRoot);
  initCheckInToggles(attendeesRoot);
  initializeAttendeeOutsideClickListener();
};

initializeOnReadyAndHtmxLoad(initializeAttendeesFeatures);

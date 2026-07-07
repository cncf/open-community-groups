import { initializeOnReadyAndHtmxLoad } from "/static/js/common/dom.js";
import "/static/js/common/modals/user-info-modal.js";
import "/static/js/common/users/user-profile-modal-triggers.js";
import "/static/js/common/users/user-search-field.js";
import {
  initializeAttendeeActionsMenu,
  initializeAttendeeOutsideClickListener,
} from "/static/js/dashboard/group/attendees/actions-menu.js";
import { initializeAnswersModal } from "/static/js/dashboard/group/attendees/answers.js";
import { initCheckInToggles } from "/static/js/dashboard/group/attendees/check-in.js";
import {
  initializeAttendeeEmailSelection,
  initializeAttendeeNotification,
} from "/static/js/dashboard/group/attendees/notification.js";
import { initializeRefundReviewModal } from "/static/js/dashboard/group/attendees/refunds.js";
import { resolveAttendeesRoot } from "/static/js/dashboard/group/attendees/shared.js";
import { initializeInvitationModal } from "/static/js/dashboard/group/attendees/invitation.js";
import { initializeQrCodeModal } from "/static/js/dashboard/group/qr-code/modal.js";

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

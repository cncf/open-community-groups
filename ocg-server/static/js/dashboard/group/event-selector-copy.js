import {
  setImageFieldValue,
  setSelectValue,
  setTextValue,
} from "/static/js/common/utils.js";
import {
  appendCopySuffix,
  setAttendeeApprovalRequired,
  setCategoryValue,
  setDiscountCodes,
  setEventReminderEnabled,
  setGalleryImages,
  setHosts,
  setPaymentCurrencyCode,
  setRegistrationQuestions,
  setRegistrationRequired,
  setSessions,
  setSponsors,
  setTags,
  setTicketTypes,
  setWaitlistEnabled,
  updateMarkdownContent,
  updateTimezone,
} from "/static/js/dashboard/group/event-form-helpers.js";

const getOnlineEventDetails = () => document.querySelector("online-event-details");

/**
 * Resets meeting-related fields to avoid copying existing links or sync state.
 */
export const resetCopiedMeetingFields = () => {
  setTextValue("meeting_join_instructions", "");
  setTextValue("meeting_join_url", "");
  setTextValue("meeting_recording_url", "");
  const meetingDetails = getOnlineEventDetails();
  if (meetingDetails && typeof meetingDetails.reset === "function") {
    meetingDetails.reset();
  }
};

/**
 * Copies reusable manual meeting access details into the event form.
 * @param {object} details Event details payload
 */
export const copyManualMeetingFields = (details) => {
  if (details.meeting_requested === true) {
    return;
  }

  const meetingFields = {
    meeting_join_instructions: details.meeting_join_instructions || "",
    meeting_join_url: details.meeting_join_url || "",
  };

  setTextValue("meeting_join_instructions", meetingFields.meeting_join_instructions);
  setTextValue("meeting_join_url", meetingFields.meeting_join_url);

  const meetingDetails = getOnlineEventDetails();
  if (meetingDetails && typeof meetingDetails.setManualMeetingDetails === "function") {
    meetingDetails.setManualMeetingDetails(meetingFields);
  }
};

/**
 * Applies copied event details into the event form.
 * @param {object} details Event details payload
 * @returns {Promise<void>}
 */
export const applyCopiedEventDetails = async (details) => {
  if (!details || typeof details !== "object") {
    return;
  }

  resetCopiedMeetingFields();
  setTextValue("name", appendCopySuffix(details.name));
  setCategoryValue(details);
  setSelectValue("kind_id", details.kind);
  setImageFieldValue("logo_url", details.logo_url);
  setTextValue("description_short", details.description_short);
  updateMarkdownContent(details.description);
  setTextValue("capacity", details.capacity);
  setEventReminderEnabled(details.event_reminder_enabled !== false);
  setRegistrationRequired(details.registration_required === true);
  setRegistrationQuestions(details.registration_questions);
  // Clear mutually exclusive enrollment state before dependent sync runs.
  setAttendeeApprovalRequired(false);
  setWaitlistEnabled(false);
  setTextValue("meetup_url", details.meetup_url);
  setTextValue("luma_url", details.luma_url);
  setGalleryImages(details.photos_urls);
  setTags(details.tags);
  setPaymentCurrencyCode(details.payment_currency_code);
  await setTicketTypes(details.ticket_types);
  setDiscountCodes(details.discount_codes);
  setWaitlistEnabled(details.waitlist_enabled === true);
  setAttendeeApprovalRequired(details.attendee_approval_required === true);
  updateTimezone(details.timezone);
  setTextValue("venue_name", details.venue_name);
  setTextValue("venue_address", details.venue_address);
  setTextValue("venue_city", details.venue_city);
  setTextValue("venue_zip_code", details.venue_zip_code);
  copyManualMeetingFields(details);
  setHosts(details.hosts);
  setSponsors(details.sponsors);
  setSessions([]);
};

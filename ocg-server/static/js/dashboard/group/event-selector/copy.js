import { setImageFieldValue, setSelectValue, setTextValue } from "/static/js/common/utils.js";
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
  setSessions,
  setSponsors,
  setTags,
  setTicketTaxConfiguration,
  setTicketTypes,
  setWaitlistEnabled,
  updateMarkdownContent,
  updateTimezone,
} from "/static/js/dashboard/group/event-form-helpers.js";

const getOnlineEventDetails = () => document.querySelector("online-event-details");
const getLocationSearchField = () => document.querySelector("location-search-field");

/**
 * Resets meeting-related fields to avoid copying existing links or sync state.
 */
const resetCopiedMeetingFields = () => {
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
const copyManualMeetingFields = (details) => {
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
 * Copies the complete physical venue into the event location component.
 * @param {object} details Event details payload
 */
const copyVenueFields = (details) => {
  const locationSearchField = getLocationSearchField();
  if (locationSearchField && typeof locationSearchField.setLocationFields === "function") {
    locationSearchField.setLocationFields({
      country: details.venue_country_name,
      countryCode: details.venue_country_code,
      latitude: details.latitude,
      longitude: details.longitude,
      state: details.venue_state,
      venueAddress: details.venue_address,
      venueCity: details.venue_city,
      venueName: details.venue_name,
      venueZipCode: details.venue_zip_code,
    });
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
  setTextValue("registration_ends_at", "");
  setTextValue("registration_starts_at", "");
  setCategoryValue(details);
  setSelectValue("kind_id", details.kind);
  setImageFieldValue("logo_url", details.logo_url);
  setImageFieldValue("banner_url", details.banner_url);
  setImageFieldValue("banner_mobile_url", details.banner_mobile_url);
  setTextValue("description_short", details.description_short);
  updateMarkdownContent(details.description);
  setEventReminderEnabled(details.event_reminder_enabled !== false);
  setRegistrationQuestions(details.registration_questions);
  // Clear mutually exclusive enrollment state before dependent sync runs.
  setAttendeeApprovalRequired(false);
  setWaitlistEnabled(false);
  setTextValue("meetup_url", details.meetup_url);
  setTextValue("luma_url", details.luma_url);
  setGalleryImages(details.photos_urls);
  setTags(details.tags);
  setPaymentCurrencyCode(details.payment_currency_code);
  setTicketTaxConfiguration(details);
  await setTicketTypes(details.ticket_types);
  setDiscountCodes(details.discount_codes);
  setWaitlistEnabled(details.waitlist_enabled === true);
  setAttendeeApprovalRequired(details.attendee_approval_required === true);
  updateTimezone(details.timezone);
  copyVenueFields(details);
  copyManualMeetingFields(details);
  setHosts(details.hosts);
  setSponsors(details.sponsors);
  setSessions([]);
};

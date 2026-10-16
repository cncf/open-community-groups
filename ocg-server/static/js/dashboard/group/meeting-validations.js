import { getElementById, setElementHidden } from "/static/js/common/dom.js";
import { getCommonAlertOptions } from "/static/js/common/alerts.js";
import { toUtcIsoInTimezone } from "/static/js/common/datetime.js";

/**
 * Zoom API limits meeting duration to 5 to 720 minutes.
 */
export const MIN_MEETING_MINUTES = 5;
export const MAX_MEETING_MINUTES = 720;
export const DEFAULT_MEETING_PROVIDER = "zoom";
const VENUE_FIELDS = ["venue_name", "venue_address", "venue_city", "venue_zip_code"];

const findVenueField = (root, fieldId) =>
  getElementById(root, fieldId) || root?.querySelector?.(`[name="${fieldId}"]`);

/**
 * Updates visibility of venue and online event sections based on event kind.
 * @param {string} kind The event kind value (virtual, in-person, hybrid)
 * @param {Document|Element} [root=document] Root container
 */
export const updateSectionVisibility = (kind, root = document) => {
  const venueSection = getElementById(root, "venue-information-section");
  const onlineSection = getElementById(root, "online-event-details-section");

  setElementHidden(venueSection, kind === "virtual");
  setElementHidden(onlineSection, kind === "in-person");
};

/**
 * Parses an event-local datetime-local value as an instant in the event timezone.
 * Falls back to the browser timezone when no event timezone is available.
 * @param {string} value Datetime-local string
 * @param {string} [timezone=""] Event IANA timezone
 * @returns {Date} Parsed date, invalid when the value cannot be parsed
 */
export const parseMeetingDateTime = (value, timezone = "") =>
  new Date(toUtcIsoInTimezone(value, timezone) ?? Number.NaN);

/**
 * Validates whether automatic meeting creation is allowed for the provided data.
 * Schedule fields are focused before the error is shown so the alert returns
 * focus to them when it closes.
 * @param {object} params Validation inputs
 * @param {boolean} params.requested Whether automatic meeting is requested
 * @param {string} params.kindValue Event kind value
 * @param {string} params.startsAtValue Start datetime-local string
 * @param {string} params.endsAtValue End datetime-local string
 * @param {number} [params.capacityValue] Event capacity value
 * @param {number} [params.capacityLimit] Meeting provider capacity limit
 * @param {boolean} [params.capacityFromTicketTypes=false] Whether tickets define capacity
 * @param {function} params.showError Function to display error messages
 * @param {function} [params.displaySection] Optional section switcher
 * @param {HTMLElement} [params.startsAtInput] Start input element to focus
 * @param {HTMLElement} [params.endsAtInput] End input element to focus
 * @param {string} [params.timezone=""] Event IANA timezone of the start and end values
 * @param {boolean} [params.validateCapacity=true] Whether capacity rules apply
 * @returns {boolean} True when valid, false otherwise
 */
export const validateMeetingRequest = ({
  requested,
  kindValue,
  startsAtValue,
  endsAtValue,
  capacityValue,
  capacityLimit,
  capacityFromTicketTypes = false,
  showError,
  displaySection,
  startsAtInput,
  endsAtInput,
  timezone = "",
  validateCapacity = true,
}) => {
  if (!requested) return true;

  if (kindValue !== "virtual" && kindValue !== "hybrid") {
    showError(
      "Automatic meetings can only be created for virtual or hybrid events. Please change the event type or disable automatic meeting creation.",
    );
    return false;
  }

  if (!startsAtValue || !endsAtValue) {
    displaySection?.("date-venue");
    if (!startsAtValue && startsAtInput) {
      startsAtInput.focus();
    } else if (endsAtInput) {
      endsAtInput.focus();
    }
    showError(
      "Automatic meetings require both start and end times to be set. Please provide the event schedule or disable automatic meeting creation.",
    );
    return false;
  }

  const startDate = parseMeetingDateTime(startsAtValue, timezone);
  const endDate = parseMeetingDateTime(endsAtValue, timezone);
  if (Number.isNaN(startDate.getTime()) || Number.isNaN(endDate.getTime())) {
    displaySection?.("date-venue");
    if (Number.isNaN(startDate.getTime())) {
      startsAtInput?.focus();
    } else {
      endsAtInput?.focus();
    }
    showError(
      "Automatic meetings need valid start and end dates. Update the schedule or disable automatic meeting creation.",
    );
    return false;
  }
  const durationMinutes = (endDate - startDate) / 60000;

  if (!Number.isFinite(durationMinutes) || durationMinutes <= 0) {
    displaySection?.("date-venue");
    endsAtInput?.focus();
    showError(
      "Automatic meetings require an end time after the start time. Update the schedule or disable automatic meeting creation.",
    );
    return false;
  }

  if (durationMinutes < MIN_MEETING_MINUTES || durationMinutes > MAX_MEETING_MINUTES) {
    displaySection?.("date-venue");
    endsAtInput?.focus();
    showError(
      `Automatic meetings must last between ${MIN_MEETING_MINUTES} and ${MAX_MEETING_MINUTES} minutes (meeting provider limits). Adjust start and end times or disable automatic meeting creation.`,
    );
    return false;
  }

  if (!validateCapacity) return true;

  if (!Number.isFinite(capacityValue) || capacityValue <= 0) {
    showError(
      capacityFromTicketTypes
        ? "Add seats to at least one ticket type before enabling automatic meeting creation."
        : "Event capacity is required for automatic meeting creation.",
    );
    displaySection?.(capacityFromTicketTypes ? "payments" : "details");
    return false;
  }

  if (Number.isFinite(capacityLimit) && capacityValue > capacityLimit) {
    showError(
      capacityFromTicketTypes
        ? `Total ticket seats (${capacityValue}) exceed the configured meeting participant limit (${capacityLimit}). Reduce ticket seats or disable automatic meeting creation.`
        : `Event capacity (${capacityValue}) exceeds the configured meeting participant limit (${capacityLimit}). Reduce capacity or disable automatic meeting creation.`,
    );
    displaySection?.(capacityFromTicketTypes ? "payments" : "details");
    return false;
  }

  return true;
};

/**
 * Checks whether any venue input field contains non-empty text.
 * @param {Document|Element} [root=document] Root container
 * @returns {boolean} True when at least one venue field has data
 */
export const hasVenueData = (root = document) =>
  VENUE_FIELDS.some((fieldId) => {
    const field = findVenueField(root, fieldId);
    return field && field.value.trim() !== "";
  });

/**
 * Clears all venue input field values if the elements exist in the DOM.
 * @param {Document|Element} [root=document] Root container
 * @returns {void}
 */
export const clearVenueFields = (root = document) => {
  VENUE_FIELDS.forEach((fieldId) => {
    const field = findVenueField(root, fieldId);
    if (field) {
      field.value = "";
      field.dispatchEvent(new Event("input", { bubbles: true }));
    }
  });

  const locationSearchField = root?.querySelector?.("location-search-field");
  if (locationSearchField && typeof locationSearchField.clearLocationFields === "function") {
    locationSearchField.clearLocationFields();
  }
};

/**
 * Prompts the user to confirm deleting venue data when switching to virtual.
 * @returns {Promise<boolean>} Resolves true when the user confirms
 */
export const confirmVenueDataDeletion = async () => {
  const result = await Swal.fire({
    text: "Switching to a virtual event will delete the venue information. Do you want to continue?",
    icon: "warning",
    showCancelButton: true,
    confirmButtonText: "Yes, delete venue info",
    cancelButtonText: "No, keep it",
    ...getCommonAlertOptions(),
    position: "center",
    backdrop: true,
  });
  return result.isConfirmed;
};

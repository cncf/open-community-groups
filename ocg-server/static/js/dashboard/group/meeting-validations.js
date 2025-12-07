/**
 * Zoom API limits meeting duration to 5 to 720 minutes.
 */
export const MIN_MEETING_MINUTES = 5;
export const MAX_MEETING_MINUTES = 720;
export const DEFAULT_MEETING_PROVIDER = "zoom";

/**
 * Validates whether automatic meeting creation is allowed for the provided data.
 * @param {object} params Validation inputs
 * @param {boolean} params.requested Whether automatic meeting is requested
 * @param {string} params.kindValue Event kind value
 * @param {string} params.startsAtValue Start datetime-local string
 * @param {string} params.endsAtValue End datetime-local string
 * @param {number} [params.capacityValue] Event capacity value
 * @param {number} [params.capacityLimit] Meeting provider capacity limit
 * @param {function} params.showError Function to display error messages
 * @param {function} [params.displaySection] Optional section switcher
 * @param {HTMLElement} [params.startsAtInput] Start input element to focus
 * @param {HTMLElement} [params.endsAtInput] End input element to focus
 * @returns {boolean} True when valid, false otherwise
 */
export const validateMeetingRequest = ({
  requested,
  kindValue,
  startsAtValue,
  endsAtValue,
  capacityValue,
  capacityLimit,
  showError,
  displaySection,
  startsAtInput,
  endsAtInput,
}) => {
  if (!requested) return true;

  if (kindValue !== "virtual" && kindValue !== "hybrid") {
    showError(
      "Automatic meetings can only be created for virtual or hybrid events. Please change the event type or disable automatic meeting creation.",
    );
    return false;
  }

  if (!startsAtValue || !endsAtValue) {
    showError(
      "Automatic meetings require both start and end times to be set. Please provide the event schedule or disable automatic meeting creation.",
    );
    displaySection?.("date-venue");
    if (!startsAtValue && startsAtInput) {
      startsAtInput.focus();
    } else if (endsAtInput) {
      endsAtInput.focus();
    }
    return false;
  }

  const startDate = new Date(startsAtValue);
  const endDate = new Date(endsAtValue);
  if (Number.isNaN(startDate.getTime()) || Number.isNaN(endDate.getTime())) {
    showError(
      "Automatic meetings need valid start and end dates. Update the schedule or disable automatic meeting creation.",
    );
    displaySection?.("date-venue");
    if (Number.isNaN(startDate.getTime())) {
      startsAtInput?.focus();
    } else {
      endsAtInput?.focus();
    }
    return false;
  }
  const durationMinutes = (endDate - startDate) / 60000;

  if (!Number.isFinite(durationMinutes) || durationMinutes <= 0) {
    showError(
      "Automatic meetings require an end time after the start time. Update the schedule or disable automatic meeting creation.",
    );
    displaySection?.("date-venue");
    endsAtInput?.focus();
    return false;
  }

  if (durationMinutes < MIN_MEETING_MINUTES || durationMinutes > MAX_MEETING_MINUTES) {
    showError(
      `Automatic meetings must last between ${MIN_MEETING_MINUTES} and ${MAX_MEETING_MINUTES} minutes (meeting provider limits). Adjust start and end times or disable automatic meeting creation.`,
    );
    displaySection?.("date-venue");
    endsAtInput?.focus();
    return false;
  }

  if (!Number.isFinite(capacityValue) || capacityValue <= 0) {
    showError("Event capacity is required for automatic meeting creation.");
    displaySection?.("details");
    return false;
  }

  if (Number.isFinite(capacityLimit) && capacityValue > capacityLimit) {
    showError(
      `Event capacity (${capacityValue}) exceeds the configured meeting participant limit (${capacityLimit}). Reduce capacity or disable automatic meeting creation.`,
    );
    displaySection?.("details");
    return false;
  }

  return true;
};

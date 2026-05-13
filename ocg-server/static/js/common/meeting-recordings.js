export const MEETING_RECORDING_URL_LEGEND =
  "Optional processed recording that takes priority over the original provider recording.";

/**
 * Returns the public visibility message for meeting recordings.
 * @param {object} options Recording visibility options.
 * @param {boolean} options.published Whether the recording is public.
 * @param {string} [options.finalUrl] Organizer-provided final recording URL.
 * @param {string} [options.rawUrl] Provider-synced recording URL.
 * @returns {string} Public visibility message.
 */
export const getMeetingRecordingVisibilityText = ({ published, finalUrl = "", rawUrl = "" }) => {
  const hasFinalUrl = Boolean((finalUrl || "").trim());
  const hasRawUrl = Boolean((rawUrl || "").trim());

  if (published !== true) {
    return "Public visitors will not see a recording link.";
  }

  if (hasFinalUrl) {
    return "Public visitors will see the final public recording URL.";
  }

  if (hasRawUrl) {
    return "Public visitors will see the original provider recording.";
  }

  return "Public visitors will not see a recording link until a recording URL is available.";
};

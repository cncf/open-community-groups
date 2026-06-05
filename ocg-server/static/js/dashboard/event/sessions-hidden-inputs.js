import { html } from "/static/vendor/js/lit-all.v3.3.1.min.js";
import { DEFAULT_MEETING_PROVIDER } from "/static/js/dashboard/group/meeting-validations.js";

/**
 * Gets normalized hidden input values for one session.
 * @param {Object} session Session payload.
 * @returns {Object} Hidden input values.
 */
export const getSessionHiddenInputValues = (session) => {
  const automaticMeetingRequested =
    session.meeting_requested === true || session.meeting_requested === "true";
  const isCfsLinkedSession = Boolean(session.cfs_submission_id);
  const meetingProviderId =
    session.meeting_provider_id ||
    session.meeting_provider ||
    (automaticMeetingRequested ? DEFAULT_MEETING_PROVIDER : "");

  return {
    automaticMeetingRequested,
    description: isCfsLinkedSession ? "" : session.description || "",
    isCfsLinkedSession,
    meetingJoinInstructions: automaticMeetingRequested
      ? ""
      : session.meeting_join_instructions || "",
    meetingJoinUrl: automaticMeetingRequested ? "" : session.meeting_join_url || "",
    meetingProviderId,
    meetingRecordingPublished: session.meeting_recording_published === true,
    meetingRecordingUrl: session.meeting_recording_url || "",
  };
};

/**
 * Renders hidden speaker inputs for one session.
 * @param {Object} state Speaker input state.
 * @returns {import("lit").TemplateResult[]|string}
 */
const renderSessionSpeakerHiddenInputs = ({ index, session, values }) => {
  if (values.isCfsLinkedSession) {
    return "";
  }

  return (session.speakers || []).map(
    (speaker, speakerIndex) => html`
      <input
        type="hidden"
        name="sessions[${index}][speakers][${speakerIndex}][user_id]"
        value=${speaker.user_id || ""}
      />
      <input
        type="hidden"
        name="sessions[${index}][speakers][${speakerIndex}][featured]"
        value=${speaker.featured || false}
      />
    `,
  );
};

/**
 * Renders hidden inputs for one session.
 * @param {Object} session Session payload.
 * @param {number} index Session index.
 * @returns {import("lit").TemplateResult}
 */
export const renderSessionHiddenInputs = (session, index) => {
  const values = getSessionHiddenInputValues(session);

  return html`
    <input type="hidden" name="sessions[${index}][session_id]" value=${session.session_id || ""} />
    <input type="hidden" name="sessions[${index}][name]" value=${session.name || ""} />
    <input type="hidden" name="sessions[${index}][kind]" value=${session.kind || ""} />
    <input type="hidden" name="sessions[${index}][starts_at]" value=${session.starts_at || ""} />
    <input type="hidden" name="sessions[${index}][ends_at]" value=${session.ends_at || ""} />
    <input type="hidden" name="sessions[${index}][location]" value=${session.location || ""} />
    <input type="hidden" name="sessions[${index}][description]" value=${values.description} />
    <input
      type="hidden"
      name="sessions[${index}][cfs_submission_id]"
      value=${session.cfs_submission_id || ""}
    />
    <input
      type="hidden"
      name="sessions[${index}][meeting_join_instructions]"
      value=${values.meetingJoinInstructions}
    />
    <input
      type="hidden"
      name="sessions[${index}][meeting_join_url]"
      value=${values.meetingJoinUrl}
    />
    <input
      type="hidden"
      name="sessions[${index}][meeting_recording_published]"
      value=${values.meetingRecordingPublished}
    />
    <input
      type="hidden"
      name="sessions[${index}][meeting_recording_url]"
      value=${values.meetingRecordingUrl}
    />
    <input
      type="hidden"
      name="sessions[${index}][meeting_requested]"
      value=${session.meeting_requested || false}
    />
    <input
      type="hidden"
      name="sessions[${index}][meeting_provider_id]"
      value=${values.meetingProviderId}
    />
    ${renderSessionSpeakerHiddenInputs({ index, session, values })}
  `;
};

/**
 * Renders hidden inputs for all sessions.
 * @param {Object[]} sessions Session payloads.
 * @returns {import("lit").TemplateResult}
 */
export const renderSessionsHiddenInputs = (sessions) => html`
  ${sessions.map((session, index) => renderSessionHiddenInputs(session, index))}
`;

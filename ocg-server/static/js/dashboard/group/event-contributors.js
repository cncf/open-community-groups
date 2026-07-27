import { markDatasetReady } from "/static/js/common/dom.js";
import { normalizeSpeakers } from "/static/js/dashboard/event/sessions/speaker-utils.js";
import "/static/js/dashboard/group/session-speakers-table.js";

/**
 * Coordinates contributor tables, bulk speaker recipients, and save-first award state.
 * @param {Document|Element} pageRoot Event page root.
 * @returns {void}
 */
export const initializeEventContributors = (pageRoot) => {
  if (!(pageRoot instanceof HTMLElement) || !markDatasetReady(pageRoot, "contributorsReady")) {
    return;
  }

  const hostsSelector = pageRoot.querySelector("#event-hosts-selector");
  const speakersSelector = pageRoot.querySelector("#event-speakers-selector");
  const sessionSpeakersTable = pageRoot.querySelector("#session-speakers-table");
  const sessionsSection = pageRoot.querySelector("sessions-section");
  if (!hostsSelector || !speakersSelector || !sessionSpeakersTable || !sessionsSection) {
    return;
  }

  let contributorChangesPending = false;

  const setAwardsDisabled = () => {
    hostsSelector.awardsDisabled = contributorChangesPending;
    speakersSelector.awardsDisabled = contributorChangesPending;
    sessionSpeakersTable.awardsDisabled = contributorChangesPending;
  };

  const syncSessionSpeakers = () => {
    const sessions = Array.isArray(sessionsSection.sessions) ? sessionsSection.sessions : [];
    sessionSpeakersTable.sessions = [...sessions];
    speakersSelector.additionalAwardUserIds = getSessionSpeakerIds(sessions);
    sessionSpeakersTable.requestUpdate?.();
    speakersSelector.requestUpdate?.();
  };

  const markContributorChangesPending = () => {
    contributorChangesPending = true;
    setAwardsDisabled();
  };

  hostsSelector.addEventListener("users-changed", markContributorChangesPending);
  speakersSelector.addEventListener("speakers-changed", markContributorChangesPending);
  sessionsSection.addEventListener("sessions-changed", () => {
    markContributorChangesPending();
    syncSessionSpeakers();
  });

  Promise.resolve(sessionsSection.updateComplete).then(() => {
    syncSessionSpeakers();
    setAwardsDisabled();
  });
};

/** Returns unique session-level speaker identifiers. */
const getSessionSpeakerIds = (sessions) => [
  ...new Set(
    (sessions || []).flatMap((session) =>
      normalizeSpeakers(session.speakers)
        .map((speaker) => speaker.user_id)
        .filter(Boolean),
    ),
  ),
];

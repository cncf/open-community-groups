import { initializeOnReadyAndHtmxLoad, markDatasetReady } from "/static/js/common/dom.js";

const AGENDA_DAY_SELECTOR = "[data-agenda-day]";
const AGENDA_EMPTY_SELECTOR = "[data-agenda-empty]";
const AGENDA_FILTER_READY_KEY = "agendaFilterReady";
const AGENDA_FILTER_SELECTOR = "[data-agenda-filter]";
const AGENDA_SELECTOR = "[data-agenda]";
const AGENDA_SESSION_SELECTOR = "[data-agenda-session]";
const AGENDA_SESSIONS_SELECTOR = "[data-agenda-sessions]";
const AGENDA_STATUS_SELECTOR = "[data-agenda-filter-status]";

/**
 * Initializes the agenda labels filter on event pages.
 * @param {Document|Element} root Root element containing the agenda
 * @param {object} [context] Initialization context
 * @param {boolean} [context.historyRestore] Whether the root came from the HTMX history cache
 */
export const initializeAgendaFilter = (root = document, { historyRestore = false } = {}) => {
  const agenda = root.matches?.(AGENDA_SELECTOR) ? root : root.querySelector?.(AGENDA_SELECTOR);
  const filter = agenda?.querySelector(AGENDA_FILTER_SELECTOR);
  if (!(agenda instanceof HTMLElement) || !filter) {
    return;
  }

  // Rebind restored snapshots and reset any stale filtered state.
  if (historyRestore) {
    delete agenda.dataset[AGENDA_FILTER_READY_KEY];
    applyAgendaFilter(agenda, filter.selected);
  }
  if (!markDatasetReady(agenda, AGENDA_FILTER_READY_KEY)) {
    return;
  }

  agenda.addEventListener("change", (event) => {
    if (event.target === filter) {
      applyAgendaFilter(agenda, filter.selected);
    }
  });
};

/**
 * Shows only the agenda sessions that have any of the selected labels.
 * @param {Element} agenda Agenda root element
 * @param {Array<string>} [selectedLabelIds] Selected event label identifiers
 */
export const applyAgendaFilter = (agenda, selectedLabelIds = []) => {
  const selected = new Set(selectedLabelIds);
  const isFiltering = selected.size > 0;
  let matchingCount = 0;
  let totalCount = 0;

  agenda.querySelectorAll(AGENDA_DAY_SELECTOR).forEach((day) => {
    // Toggle each session of the day based on its labels.
    const sessions = day.querySelectorAll(AGENDA_SESSION_SELECTOR);
    let dayMatchingCount = 0;
    sessions.forEach((session) => {
      const matches = !isFiltering || sessionLabelIds(session).some((id) => selected.has(id));
      session.toggleAttribute("hidden", !matches);
      if (matches) {
        dayMatchingCount += 1;
      }
    });

    // Swap the day sessions list for the empty message when nothing matches.
    const hasMatches = dayMatchingCount > 0;
    day.querySelector(AGENDA_SESSIONS_SELECTOR)?.toggleAttribute("hidden", !hasMatches);
    day.querySelector(AGENDA_EMPTY_SELECTOR)?.toggleAttribute("hidden", hasMatches);

    matchingCount += dayMatchingCount;
    totalCount += sessions.length;
  });

  // Announce the filter result to assistive technologies.
  const status = agenda.querySelector(AGENDA_STATUS_SELECTOR);
  if (status) {
    status.textContent = isFiltering ? `Showing ${matchingCount} of ${totalCount} sessions.` : "";
  }
};

/**
 * Reads the label identifiers assigned to an agenda session.
 * @param {Element} session Agenda session element
 * @returns {Array<string>}
 */
const sessionLabelIds = (session) =>
  (session.getAttribute("data-label-ids") || "").split(/\s+/).filter(Boolean);

initializeOnReadyAndHtmxLoad(initializeAgendaFilter);

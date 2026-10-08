import { expect } from "@open-wc/testing";

import { initializeAgendaFilter } from "/static/js/event/agenda-filter.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

describe("event agenda filter", () => {
  afterEach(() => {
    resetDom();
  });

  it("shows sessions matching any selected label", () => {
    // Render the agenda and select two labels.
    renderAgenda();
    initializeAgendaFilter();
    selectLabels(["label-ai", "label-room"]);

    // Only sessions with either label stay visible.
    expect(visibleSessionNames()).to.deep.equal(["AI keynote", "Room A workshop", "AI security panel"]);
    expect(statusText()).to.equal("Showing 3 of 4 sessions.");
  });

  it("shows the empty message for days without matching sessions", () => {
    // Render the agenda and select a label used only on the first day.
    renderAgenda();
    initializeAgendaFilter();
    selectLabels(["label-room"]);

    // The first day keeps its list while the second day shows the empty message.
    const [firstDay, secondDay] = document.querySelectorAll("[data-agenda-day]");
    expect(firstDay.querySelector("[data-agenda-sessions]").hidden).to.equal(false);
    expect(firstDay.querySelector("[data-agenda-empty]").hidden).to.equal(true);
    expect(secondDay.querySelector("[data-agenda-sessions]").hidden).to.equal(true);
    expect(secondDay.querySelector("[data-agenda-empty]").hidden).to.equal(false);
    expect(statusText()).to.equal("Showing 1 of 4 sessions.");
  });

  it("restores every session when the selection is cleared", () => {
    // Render the agenda, filter it and clear the selection.
    renderAgenda();
    initializeAgendaFilter();
    selectLabels(["label-room"]);
    selectLabels([]);

    // Every session and list is visible again and no status is announced.
    expect(visibleSessionNames()).to.have.length(4);
    document.querySelectorAll("[data-agenda-sessions]").forEach((list) => {
      expect(list.hidden).to.equal(false);
    });
    document.querySelectorAll("[data-agenda-empty]").forEach((message) => {
      expect(message.hidden).to.equal(true);
    });
    expect(statusText()).to.equal("");
  });

  it("ignores change events from other agenda elements", () => {
    // Render the agenda with a pending selection and an unrelated input.
    renderAgenda();
    initializeAgendaFilter();
    document.querySelector("[data-agenda-filter]").selected = ["label-room"];
    const input = document.createElement("input");
    document.querySelector("[data-agenda]").append(input);

    // Dispatch a change event from the unrelated input.
    input.dispatchEvent(new Event("change", { bubbles: true }));

    // The agenda stays unfiltered.
    expect(visibleSessionNames()).to.have.length(4);
    expect(statusText()).to.equal("");
  });

  it("binds the change listener only once", () => {
    // Render the agenda and initialize it twice.
    renderAgenda();
    initializeAgendaFilter();
    initializeAgendaFilter();
    let filterCalls = 0;
    const status = document.querySelector("[data-agenda-filter-status]");
    const observer = new MutationObserver((mutations) => {
      filterCalls += mutations.length;
    });
    observer.observe(status, { childList: true });

    // Apply a selection and flush the observed mutations.
    selectLabels(["label-ai"]);
    filterCalls += observer.takeRecords().length;
    observer.disconnect();

    // The status is written by a single listener.
    expect(filterCalls).to.equal(1);
  });

  it("resets stale filtered state restored from history", () => {
    // Render an agenda snapshot with filtered state and an empty selection.
    renderAgenda();
    const agenda = document.querySelector("[data-agenda]");
    agenda.dataset.agendaFilterReady = "true";
    agenda.querySelectorAll("[data-agenda-session]").forEach((session) => {
      session.hidden = true;
    });

    // Initialize the restored agenda.
    initializeAgendaFilter(document, { historyRestore: true });

    // Every session is visible and the filter listener is bound again.
    expect(visibleSessionNames()).to.have.length(4);
    selectLabels(["label-ai"]);
    expect(visibleSessionNames()).to.deep.equal(["AI keynote", "AI security panel"]);
  });
});

/**
 * Renders a two-day agenda fixture with a stand-in labels filter.
 */
const renderAgenda = () => {
  document.body.innerHTML = `
    <div data-agenda>
      <div data-agenda-filter></div>
      <p data-agenda-filter-status role="status"></p>
      <div data-agenda-day>
        <ol data-agenda-sessions>
          <li data-agenda-session data-label-ids="label-ai">AI keynote</li>
          <li data-agenda-session data-label-ids="label-room">Room A workshop</li>
        </ol>
        <p data-agenda-empty hidden>No sessions match the selected labels.</p>
      </div>
      <div data-agenda-day>
        <ol data-agenda-sessions>
          <li data-agenda-session data-label-ids="label-security label-ai">AI security panel</li>
          <li data-agenda-session data-label-ids="">Closing</li>
        </ol>
        <p data-agenda-empty hidden>No sessions match the selected labels.</p>
      </div>
    </div>
  `;
  document.querySelector("[data-agenda-filter]").selected = [];
};

/**
 * Updates the stand-in filter selection and dispatches its change event.
 * @param {Array<string>} labelIds Selected label identifiers
 */
const selectLabels = (labelIds) => {
  const filter = document.querySelector("[data-agenda-filter]");
  filter.selected = labelIds;
  filter.dispatchEvent(new Event("change", { bubbles: true }));
};

/**
 * Reads the agenda status text.
 * @returns {string}
 */
const statusText = () => document.querySelector("[data-agenda-filter-status]").textContent;

/**
 * Lists the visible agenda session names.
 * @returns {Array<string>}
 */
const visibleSessionNames = () =>
  [...document.querySelectorAll("[data-agenda-session]")]
    .filter((session) => !session.hidden)
    .map((session) => session.textContent.trim());

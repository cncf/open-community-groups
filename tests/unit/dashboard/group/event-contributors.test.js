import { expect } from "@open-wc/testing";

import "/static/js/common/users/user-search-selector.js";
import { initializeEventContributors } from "/static/js/dashboard/group/event-contributors.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

const ORGANIZERS = [
  { name: "Grace Hopper", user_id: "9", username: "grace" },
  { name: "Ada Lovelace", user_id: "7", username: "ada" },
];

/**
 * Mounts the Contributors tab fixture used by the event pages.
 * @param {object} [options] Fixture options.
 * @param {boolean} [options.withOrganizers] Whether the organizers selector is rendered.
 * @returns {Promise<HTMLElement>} Event page root.
 */
const mountContributors = async ({ withOrganizers = true } = {}) => {
  document.body.innerHTML = `
    <div data-event-page="update">
      <form id="contributors-form" data-event-form>
        <speakers-selector id="event-speakers-selector"></speakers-selector>
        <session-speakers-table id="session-speakers-table"></session-speakers-table>
        <user-search-selector id="event-hosts-selector" field-name="hosts" display-mode="table" label="host"></user-search-selector>
        ${
          withOrganizers
            ? `<button id="event-organizers-award-button" type="button" data-badge-award-open disabled>Award badge</button>
               <user-search-selector id="event-organizers-selector"
                                     selected-users='${JSON.stringify(ORGANIZERS)}'
                                     field-name="organizers"
                                     dashboard-type="group"
                                     display-mode="table"
                                     event-id="event-1"
                                     can-award-badges
                                     award-button-id="event-organizers-award-button"
                                     label="organizer"></user-search-selector>
               <input type="hidden" name="organizers_present" value="true">`
            : ""
        }
      </form>
      <sessions-section></sessions-section>
    </div>
  `;

  const pageRoot = document.querySelector("[data-event-page]");
  await Promise.all(
    [...pageRoot.querySelectorAll("user-search-selector, session-speakers-table")].map(
      (element) => element.updateComplete,
    ),
  );
  return pageRoot;
};

describe("event contributors", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
  });

  it("keeps awards enabled for pre-filled organizers", async () => {
    // Render and initialize the Contributors tab with stored organizers.
    const pageRoot = await mountContributors();
    const organizersSelector = pageRoot.querySelector("#event-organizers-selector");
    initializeEventContributors(pageRoot);
    await waitForMicrotask();
    await organizersSelector.updateComplete;

    // Verify hydration does not mark contributor changes as pending.
    const awardButton = pageRoot.querySelector("#event-organizers-award-button");
    expect(organizersSelector.awardsDisabled).to.equal(false);
    expect(awardButton.disabled).to.equal(false);
    expect(awardButton.dataset.userIds).to.equal("9,7");
    expect(awardButton.dataset.eventId).to.equal("event-1");
  });

  it("disables awards on every contributor table after an organizer change", async () => {
    // Render and initialize the Contributors tab.
    const pageRoot = await mountContributors();
    initializeEventContributors(pageRoot);
    await waitForMicrotask();

    // Remove one organizer through the selector.
    const organizersSelector = pageRoot.querySelector("#event-organizers-selector");
    organizersSelector._removeUser("ada");
    await organizersSelector.updateComplete;

    // Verify all contributor components require saving before awarding.
    expect(pageRoot.querySelector("#event-hosts-selector").awardsDisabled).to.equal(true);
    expect(organizersSelector.awardsDisabled).to.equal(true);
    expect(pageRoot.querySelector("#event-speakers-selector").awardsDisabled).to.equal(true);
    expect(pageRoot.querySelector("#session-speakers-table").awardsDisabled).to.equal(true);

    // Verify the external organizer award button follows the pending state.
    const awardButton = pageRoot.querySelector("#event-organizers-award-button");
    expect(awardButton.disabled).to.equal(true);
    expect(awardButton.dataset.userIds).to.equal("9");
    expect(awardButton.title).to.equal("Save contributor changes before awarding badges.");
  });

  it("initializes the contributor wiring only once per page root", async () => {
    // Track organizer listener registrations.
    const pageRoot = await mountContributors();
    const organizersSelector = pageRoot.querySelector("#event-organizers-selector");
    const registeredEvents = [];
    const originalAddEventListener = organizersSelector.addEventListener.bind(organizersSelector);
    organizersSelector.addEventListener = (type, ...args) => {
      registeredEvents.push(type);
      originalAddEventListener(type, ...args);
    };

    // Initialize the same page root twice.
    initializeEventContributors(pageRoot);
    initializeEventContributors(pageRoot);
    await waitForMicrotask();

    // Verify the listener is registered once.
    expect(pageRoot.dataset.contributorsReady).to.equal("true");
    expect(registeredEvents.filter((type) => type === "users-changed")).to.have.length(1);
  });

  it("does nothing when the organizers selector is missing", async () => {
    // Render and initialize the Contributors tab without organizers.
    const pageRoot = await mountContributors({ withOrganizers: false });
    initializeEventContributors(pageRoot);
    await waitForMicrotask();

    // Change hosts and verify no award state is wired.
    const hostsSelector = pageRoot.querySelector("#event-hosts-selector");
    hostsSelector.dispatchEvent(new CustomEvent("users-changed", { bubbles: true, detail: { users: [] } }));
    expect(hostsSelector.awardsDisabled).to.equal(false);
    expect(pageRoot.querySelector("#session-speakers-table").awardsDisabled).to.equal(false);
  });
});

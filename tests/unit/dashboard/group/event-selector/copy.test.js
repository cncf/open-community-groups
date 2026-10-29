import { expect } from "@open-wc/testing";

import "/static/js/common/media/image-field.js";
import { applyCopiedEventDetails } from "/static/js/dashboard/group/event-selector/copy.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";

const TEAM_MEMBERS = [
  { name: "Team Lead", user_id: "team-1", username: "team-lead" },
  { name: "Team Member", user_id: "team-2", username: "team-member" },
];

/**
 * Renders the add page organizers selector with the team as available and selected users.
 * @returns {HTMLElement} Organizers selector element.
 */
const mountOrganizersSelector = () => {
  document.body.innerHTML = `
    <user-search-selector
      id="event-organizers-selector"
      field-name="organizers"
      available-users='${JSON.stringify(TEAM_MEMBERS)}'
    ></user-search-selector>
  `;
  const selector = document.querySelector("#event-organizers-selector");
  selector.selectedUsers = [...TEAM_MEMBERS];
  return selector;
};

describe("event selector copy", () => {
  beforeEach(() => {
    resetDom();
  });

  afterEach(() => {
    resetDom();
  });

  it("copies only the source event's own logo", async () => {
    // Render the logo field with a value from a previous copy.
    document.body.innerHTML = `<image-field name="logo_url" value="https://example.com/previous.png"></image-field>`;
    const logoField = document.querySelector('image-field[name="logo_url"]');
    await logoField.updateComplete;

    // Copy an event whose logo falls back to the group logo.
    await applyCopiedEventDetails({
      logo_url: "https://example.com/group-logo.png",
      name: "Fallback logo event",
    });

    // Verify the fallback logo is not copied into the form.
    expect(logoField.value).to.equal("");

    // Copy an event with its own logo.
    await applyCopiedEventDetails({
      custom_logo_url: "https://example.com/event-logo.png",
      logo_url: "https://example.com/event-logo.png",
      name: "Own logo event",
    });

    // Verify the own logo is copied into the form.
    expect(logoField.value).to.equal("https://example.com/event-logo.png");
  });

  it("replaces organizers with the source organizers still on the team", async () => {
    // Render the organizers selector and copy an event with organizers.
    const selector = mountOrganizersSelector();
    await applyCopiedEventDetails({
      name: "Source event",
      organizers: [
        { user: { user_id: "team-2", username: "team-member" } },
        { name: "Former Organizer", user_id: "former-1", username: "former" },
        { name: "Team Lead", user_id: "team-1", username: "team-lead" },
      ],
    });

    // Verify the copied organizers keep the source order and drop people outside the team.
    expect(selector.selectedUsers).to.deep.equal([
      { user_id: "team-2", username: "team-member" },
      { name: "Team Lead", user_id: "team-1", username: "team-lead" },
    ]);
  });

  it("restores the team default when no source organizer is on the team", async () => {
    // Render the organizers selector and copy an event organized by former members.
    const selector = mountOrganizersSelector();
    selector.selectedUsers = [];
    await applyCopiedEventDetails({
      name: "Source event",
      organizers: [{ name: "Former Organizer", user_id: "former-1", username: "former" }],
    });

    // Verify the team default replaces the unavailable organizers.
    expect(selector.selectedUsers).to.deep.equal(TEAM_MEMBERS);
  });

  it("restores the team default when the source has no organizers", async () => {
    // Render the organizers selector after an editor removed everyone.
    const selector = mountOrganizersSelector();
    selector.selectedUsers = [];

    // Copy events with an empty and a missing organizers list.
    await applyCopiedEventDetails({ name: "Source event", organizers: [] });
    expect(selector.selectedUsers).to.deep.equal(TEAM_MEMBERS);
    selector.selectedUsers = [];
    await applyCopiedEventDetails({ name: "Legacy event" });

    // Verify the team default is restored from the attribute.
    expect(selector.selectedUsers).to.deep.equal(TEAM_MEMBERS);
  });

  it("restores the team default after copying a source with organizers", async () => {
    // Copy an event with organizers first.
    const selector = mountOrganizersSelector();
    await applyCopiedEventDetails({
      name: "First source",
      organizers: [{ user_id: "team-2", username: "team-member" }],
    });
    expect(selector.selectedUsers).to.deep.equal([{ user_id: "team-2", username: "team-member" }]);

    // Copy an event without organizers next.
    await applyCopiedEventDetails({ name: "Second source", organizers: [] });

    // Verify the default comes from the attribute, not the previous copy.
    expect(selector.selectedUsers).to.deep.equal(TEAM_MEMBERS);
  });
});

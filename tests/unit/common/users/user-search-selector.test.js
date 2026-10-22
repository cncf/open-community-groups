import { expect } from "@open-wc/testing";

import "/static/js/common/users/user-search-selector.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { mockSwal } from "/tests/unit/test-utils/globals.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

describe("user-search-selector", () => {
  const userSearchFieldPrototype = customElements.get("user-search-field").prototype;
  const originalFocusInput = userSearchFieldPrototype.focusInput;

  useMountedElementsCleanup("user-search-selector");

  afterEach(() => {
    document.querySelector("[data-test-external-host-award]")?.remove();
    userSearchFieldPrototype.focusInput = originalFocusInput;
  });

  it("focuses the search field when the inline panel is opened", async () => {
    // Track focus calls from the nested search field.
    let focusCalls = 0;
    userSearchFieldPrototype.focusInput = () => {
      focusCalls += 1;
    };

    // Render the user-search-selector fixture.
    const element = await mountLitComponent("user-search-selector");
    element._openModal();
    await element.updateComplete;
    await Promise.resolve();

    // Focuses the search field when the inline panel is opened.
    expect(focusCalls).to.equal(1);
  });

  it("keeps the host table visible with an empty-state row", async () => {
    const element = await mountLitComponent("user-search-selector", {
      displayMode: "table",
      selectedUsers: [{ user_id: "7", username: "ada", name: "Ada Lovelace" }],
    });
    const table = element.querySelector('table[aria-label="Event hosts"]');

    // Verify the host defaults apply without a label.
    expect(table.querySelector("th").textContent.trim()).to.equal("Host");
    expect(table.querySelector("summary").getAttribute("aria-label")).to.equal(
      "Open host actions for Ada Lovelace",
    );

    // Remove the user and verify the host empty state.
    element._removeUser("ada");
    await element.updateComplete;
    const emptyState = table.querySelector("tbody td");
    expect(emptyState.textContent.trim()).to.equal("No hosts added yet.");
    expect(emptyState.getAttribute("colspan")).to.equal("2");
    expect(emptyState.classList.contains("text-center")).to.equal(true);
  });

  it("uses the label for organizer table copy", async () => {
    // Render an organizer table with one selected user.
    const element = await mountLitComponent("user-search-selector", {
      canAwardBadges: true,
      displayMode: "table",
      eventId: "event-1",
      label: "organizer",
      selectedUsers: [{ user_id: "7", username: "ada", name: "Ada Lovelace" }],
    });

    // Verify the header, accessible name, and row action copy.
    const table = element.querySelector('table[aria-label="Event organizers"]');
    expect(table).to.not.equal(null);
    expect(element.querySelector('table[aria-label="Event hosts"]')).to.equal(null);
    expect(table.querySelector("th").textContent.trim()).to.equal("Organizer");
    expect(table.querySelector("summary").getAttribute("aria-label")).to.equal(
      "Open organizer actions for Ada Lovelace",
    );

    // Remove the user and verify the organizer empty state.
    element._removeUser("ada");
    await element.updateComplete;
    expect(table.querySelector("tbody td").textContent.trim()).to.equal("No organizers added yet.");
  });

  it("limits the nested search to the available users", async () => {
    // Render one selector searching every user and one limited to the team.
    const openSelector = await mountLitComponent("user-search-selector");
    const teamSelector = await mountLitComponent("user-search-selector", {
      availableUsers: [
        { user_id: "7", username: "ada", name: "Ada Lovelace" },
        { user_id: "8", username: "grace", name: "Grace Hopper" },
      ],
      selectedUsers: [{ user_id: "7", username: "ada", name: "Ada Lovelace" }],
    });

    // Verify only the team selector searches a local list.
    expect(openSelector.querySelector("user-search-field").localUsers).to.equal(null);
    const teamField = teamSelector.querySelector("user-search-field");
    expect(teamField.localUsers.map((user) => user.username)).to.deep.equal(["ada", "grace"]);

    // Search the team and verify selected users are listed but disabled.
    teamField._handleSearchInput({ target: { value: "a" } });
    await teamField.updateComplete;
    expect(teamField._searchResults.map((user) => user.username)).to.deep.equal(["ada", "grace"]);
    const resultRows = [...teamField.querySelectorAll("[aria-disabled]")];
    expect(resultRows.map((row) => row.getAttribute("aria-disabled"))).to.deep.equal(["true", "false"]);

    // Clicking the disabled row does not add the user again.
    resultRows[0].click();
    await teamSelector.updateComplete;
    expect(teamSelector.selectedUsers.map((user) => user.username)).to.deep.equal(["ada"]);
  });

  it("confirms before removing former team members", async () => {
    // Render an organizer table with one current and one former team member.
    const swal = mockSwal();
    const element = await mountLitComponent("user-search-selector", {
      availableUsers: [{ user_id: "7", username: "ada", name: "Ada Lovelace" }],
      displayMode: "table",
      label: "organizer",
      selectedUsers: [
        { user_id: "7", username: "ada", name: "Ada Lovelace" },
        { user_id: "8", username: "grace", name: "Grace Hopper" },
      ],
    });
    const deleteButton = (username) =>
      [...element.querySelectorAll("tbody tr")]
        .find((row) => row.textContent.includes(`@${username}`))
        .querySelector(".icon-trash")
        .closest("button");

    try {
      // Cancelling the confirmation keeps the former team member.
      swal.setNextResult({ isConfirmed: false });
      deleteButton("grace").click();
      await waitForMicrotask();
      expect(swal.calls).to.have.length(1);
      expect(swal.calls[0].text).to.equal(
        "Grace Hopper is no longer on the group team, so they can't be added back once removed. Remove them anyway?",
      );
      expect(element.selectedUsers.map((user) => user.username)).to.deep.equal(["ada", "grace"]);

      // Confirming removes the former team member.
      swal.setNextResult({ isConfirmed: true });
      deleteButton("grace").click();
      await waitForMicrotask();
      expect(element.selectedUsers.map((user) => user.username)).to.deep.equal(["ada"]);

      // Current team members are removed without confirmation.
      await element.updateComplete;
      deleteButton("ada").click();
      await waitForMicrotask();
      expect(swal.calls).to.have.length(2);
      expect(element.selectedUsers).to.deep.equal([]);
    } finally {
      swal.restore();
    }
  });

  it("adds and removes selected users while honoring maxUsers", async () => {
    // Render the user-search-selector fixture.
    const element = await mountLitComponent("user-search-selector", {
      maxUsers: 1,
      fieldName: "reviewers",
    });

    // Select the user result.
    element._handleUserSelected({
      detail: {
        user: { user_id: "7", username: "ada", name: "Ada Lovelace" },
      },
    });
    element._handleUserSelected({
      detail: {
        user: { user_id: "8", username: "grace", name: "Grace Hopper" },
      },
    });
    await element.updateComplete;

    // Added and removes selected users while honoring maxUsers.
    expect(element.selectedUsers).to.deep.equal([{ user_id: "7", username: "ada", name: "Ada Lovelace" }]);
    expect(element.querySelector("selected-user-pill")?.textContent).to.include("Ada Lovelace");
    expect(element.querySelector('input[type="hidden"]').value).to.equal("7");

    // Remove the selected user.
    element._removeUser("ada");
    await element.updateComplete;

    // Added and removes selected users while honoring maxUsers.
    expect(element.selectedUsers).to.deep.equal([]);
  });

  it("renders host award and delete actions in table mode", async () => {
    const element = await mountLitComponent("user-search-selector", {
      canAwardBadges: true,
      displayMode: "table",
      eventId: "event-1",
      selectedUsers: [{ user_id: "7", username: "ada", name: "Ada Lovelace" }],
      showAwardAll: true,
    });

    expect(element.querySelector('table[aria-label="Event hosts"]')).to.not.equal(null);
    expect(element.querySelectorAll("[data-badge-award-open]")).to.have.length(2);
    const bulkAwardButton = element.querySelector("[data-badge-award-open]");
    expect(bulkAwardButton.dataset.userIds).to.equal("7");
    expect(bulkAwardButton.textContent.trim()).to.equal("Award badge");
    expect(bulkAwardButton.classList.contains("btn-mini")).to.equal(false);

    element.awardsDisabled = true;
    await element.updateComplete;
    expect(
      [...element.querySelectorAll("[data-badge-award-open]")].every((button) => button.disabled),
    ).to.equal(true);

    element.querySelector(".icon-trash")?.closest("button")?.click();
    await element.updateComplete;
    expect(element.selectedUsers).to.deep.equal([]);
  });

  it("synchronizes an external bulk award button", async () => {
    const awardButton = document.createElement("button");
    awardButton.id = "external-host-award";
    awardButton.dataset.testExternalHostAward = "";
    awardButton.dataset.badgeAwardOpen = "";
    awardButton.disabled = true;
    document.body.append(awardButton);
    const element = await mountLitComponent("user-search-selector", {
      awardButtonId: awardButton.id,
      canAwardBadges: true,
      eventId: "event-1",
      selectedUsers: [{ user_id: "7", username: "ada", name: "Ada Lovelace" }],
    });

    expect(awardButton.disabled).to.equal(false);
    expect(awardButton.dataset.eventId).to.equal("event-1");
    expect(awardButton.dataset.userIds).to.equal("7");

    element.awardsDisabled = true;
    await element.updateComplete;

    expect(awardButton.disabled).to.equal(true);
    expect(awardButton.title).to.equal("Save contributor changes before awarding badges.");
  });

  it("synchronizes organizer recipients on an external bulk award button", async () => {
    // Create the external organizer award button.
    const awardButton = document.createElement("button");
    awardButton.id = "external-organizer-award";
    awardButton.dataset.testExternalHostAward = "";
    awardButton.dataset.badgeAwardOpen = "";
    awardButton.disabled = true;
    document.body.append(awardButton);

    // Render organizers in their submitted order.
    const element = await mountLitComponent("user-search-selector", {
      awardButtonId: awardButton.id,
      canAwardBadges: true,
      displayMode: "table",
      eventId: "event-1",
      fieldName: "organizers",
      label: "organizer",
      selectedUsers: [
        { user_id: "9", username: "grace", name: "Grace Hopper" },
        { user_id: "7", username: "ada", name: "Ada Lovelace" },
      ],
    });

    // Verify recipients keep the selector order and include the event.
    expect(awardButton.disabled).to.equal(false);
    expect(awardButton.dataset.eventId).to.equal("event-1");
    expect(awardButton.dataset.userIds).to.equal("9,7");
    expect(
      [...element.querySelectorAll('input[name="organizers[]"]')].map((input) => input.value),
    ).to.deep.equal(["9", "7"]);

    // Disable awards while contributor changes are pending.
    element.awardsDisabled = true;
    await element.updateComplete;
    expect(awardButton.disabled).to.equal(true);

    // Re-enable awards after saving, then empty the list.
    element.awardsDisabled = false;
    await element.updateComplete;
    expect(awardButton.disabled).to.equal(false);
    element.selectedUsers = [];
    await element.updateComplete;
    expect(awardButton.disabled).to.equal(true);
    expect(awardButton.dataset.userIds).to.equal("");
  });
});

import { expect } from "@open-wc/testing";

import "/static/js/common/users/user-search-selector.js";
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
    });
    const table = element.querySelector('table[aria-label="Event hosts"]');
    const emptyState = table.querySelector("tbody td");

    expect(table.querySelector("th").textContent.trim()).to.equal("Host");
    expect(emptyState.textContent.trim()).to.equal("No hosts added yet.");
    expect(emptyState.getAttribute("colspan")).to.equal("2");
    expect(emptyState.classList.contains("text-center")).to.equal(true);
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
});

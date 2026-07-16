import { expect } from "@open-wc/testing";

import "/static/js/common/users/user-search-selector.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

describe("user-search-selector", () => {
  const userSearchFieldPrototype = customElements.get("user-search-field").prototype;
  const originalFocusInput = userSearchFieldPrototype.focusInput;

  useMountedElementsCleanup("user-search-selector");

  afterEach(() => {
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
    expect(element.querySelector("[data-badge-award-open]").dataset.userIds).to.equal("7");

    element.awardsDisabled = true;
    await element.updateComplete;
    expect(
      [...element.querySelectorAll("[data-badge-award-open]")].every((button) => button.disabled),
    ).to.equal(true);

    element.querySelector(".icon-trash")?.closest("button")?.click();
    await element.updateComplete;
    expect(element.selectedUsers).to.deep.equal([]);
  });
});

import { expect } from "@open-wc/testing";

import "/static/js/common/user-search-selector.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mountLitComponent, removeMountedElements } from "/tests/unit/test-utils/lit.js";

describe("user-search-selector", () => {
  const userSearchFieldPrototype = customElements.get("user-search-field").prototype;
  const originalFocusInput = userSearchFieldPrototype.focusInput;

  afterEach(() => {
    userSearchFieldPrototype.focusInput = originalFocusInput;
    removeMountedElements("user-search-selector");
    resetDom();
  });

  it("focuses the search field when the inline panel is opened", async () => {
    let focusCalls = 0;
    userSearchFieldPrototype.focusInput = () => {
      focusCalls += 1;
    };

    const element = await mountLitComponent("user-search-selector");
    element._openModal();
    await element.updateComplete;
    await Promise.resolve();

    expect(focusCalls).to.equal(1);
  });

  it("adds and removes selected users while honoring maxUsers", async () => {
    const element = await mountLitComponent("user-search-selector", {
      maxUsers: 1,
      fieldName: "reviewers",
    });

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

    expect(element.selectedUsers).to.deep.equal([{ user_id: "7", username: "ada", name: "Ada Lovelace" }]);
    expect(element.querySelector('input[type="hidden"]').value).to.equal("7");

    element._removeUser("ada");
    await element.updateComplete;

    expect(element.selectedUsers).to.deep.equal([]);
  });
});

import { expect } from "@open-wc/testing";

import "/static/js/dashboard/event/session-speaker-modal.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

describe("session-speaker-modal", () => {
  const userSearchFieldPrototype = customElements.get("user-search-field").prototype;
  const originalFocusInput = userSearchFieldPrototype.focusInput;

  useMountedElementsCleanup("session-speaker-modal");

  afterEach(() => {
    userSearchFieldPrototype.focusInput = originalFocusInput;
  });

  it("opens by resetting state, locking body scroll, and focusing the search field", async () => {
    let focusCalls = 0;
    userSearchFieldPrototype.focusInput = () => {
      focusCalls += 1;
    };

    const element = await mountLitComponent("session-speaker-modal", {
      _selectedUser: {
        user_id: "user-1",
        name: "Ada Lovelace",
      },
      _featured: true,
    });

    element.open();
    await element.updateComplete;
    await Promise.resolve();

    expect(element._isOpen).to.equal(true);
    expect(element._selectedUser).to.equal(null);
    expect(element._featured).to.equal(false);
    expect(document.body.style.overflow).to.equal("hidden");
    expect(document.body.dataset.modalOpenCount).to.equal("1");
    expect(focusCalls).to.equal(1);
  });

  it("ignores disabled users and accepts selectable ones", async () => {
    const element = await mountLitComponent("session-speaker-modal", {
      disabledUserIds: ["42"],
    });

    element._handleUserSelected({
      detail: {
        user: {
          user_id: "42",
          name: "Grace Hopper",
        },
      },
    });

    expect(element._selectedUser).to.equal(null);

    element._handleUserSelected({
      detail: {
        user: {
          user_id: "84",
          name: "Margaret Hamilton",
          username: "margaret",
        },
      },
    });

    expect(element._selectedUser).to.deep.equal({
      user_id: "84",
      name: "Margaret Hamilton",
      username: "margaret",
    });
  });

  it("emits speaker-selected with the featured state and closes the modal", async () => {
    const element = await mountLitComponent("session-speaker-modal");
    const receivedEvents = [];

    element.addEventListener("speaker-selected", (event) => {
      receivedEvents.push(event.detail);
    });

    element.open();
    await element.updateComplete;

    element._selectedUser = {
      user_id: "user-7",
      name: "Ada Lovelace",
      username: "ada",
    };
    element._toggleFeatured({
      target: {
        checked: true,
      },
    });
    element._confirmSelection();

    expect(receivedEvents).to.deep.equal([
      {
        user: {
          user_id: "user-7",
          name: "Ada Lovelace",
          username: "ada",
        },
        featured: true,
      },
    ]);
    expect(element._isOpen).to.equal(false);
    expect(element._selectedUser).to.equal(null);
    expect(element._featured).to.equal(false);
    expect(document.body.style.overflow).to.equal("");
    expect(document.body.dataset.modalOpenCount).to.equal("0");
  });

  it("closes on escape once the modal is open", async () => {
    const element = await mountLitComponent("session-speaker-modal");

    element.open();
    await element.updateComplete;

    element._onKeydown({
      key: "Escape",
    });

    expect(element._isOpen).to.equal(false);
    expect(document.body.style.overflow).to.equal("");
    expect(document.body.dataset.modalOpenCount).to.equal("0");
  });
});

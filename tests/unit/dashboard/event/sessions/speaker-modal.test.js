import { expect } from "@open-wc/testing";

import "/static/js/dashboard/event/sessions/speaker-modal.js";
import { mountLitComponent, useMountedElementsCleanup } from "/tests/unit/test-utils/lit.js";

describe("session-speaker-modal", () => {
  const userSearchFieldPrototype = customElements.get("user-search-field").prototype;
  const originalFocusInput = userSearchFieldPrototype.focusInput;

  useMountedElementsCleanup("session-speaker-modal");

  afterEach(() => {
    userSearchFieldPrototype.focusInput = originalFocusInput;
  });

  it("opens by resetting state, locking body scroll, and focusing the search field", async () => {
    // Prepare focus calls for opening by resetting state, locking body scroll.
    let focusCalls = 0;
    userSearchFieldPrototype.focusInput = () => {
      focusCalls += 1;
    };

    // Call mount lit component.
    const element = await mountLitComponent("session-speaker-modal", {
      _selectedUser: {
        user_id: "user-1",
        name: "Ada Lovelace",
      },
      _featured: true,
    });

    // Verify opens by resetting state, locking body scroll.
    element.open();
    await element.updateComplete;
    await Promise.resolve();

    // Verify opens by resetting state, locking body scroll, and focusing the search.
    expect(element._isOpen).to.equal(true);
    expect(element._selectedUser).to.equal(null);
    expect(element._featured).to.equal(false);
    expect(document.body.style.overflow).to.equal("hidden");
    expect(document.body.dataset.modalOpenCount).to.equal("1");
    expect(focusCalls).to.equal(1);
  });

  it("ignores disabled users and accepts selectable ones", async () => {
    // Call mount lit component.
    const element = await mountLitComponent("session-speaker-modal", {
      disabledUserIds: ["42"],
    });

    // Call the user selection handler.
    element._handleUserSelected({
      detail: {
        user: {
          user_id: "42",
          name: "Grace Hopper",
        },
      },
    });

    // Disabled users are ignored while selectable users remain active.
    expect(element._selectedUser).to.equal(null);

    // Call the handler with a selectable user.
    element._handleUserSelected({
      detail: {
        user: {
          user_id: "84",
          name: "Margaret Hamilton",
          username: "margaret",
        },
      },
    });

    // Selecting an enabled user updates the active selection.
    expect(element._selectedUser).to.deep.equal({
      user_id: "84",
      name: "Margaret Hamilton",
      username: "margaret",
    });
  });

  it("emits speaker-selected with the featured state and closes the modal", async () => {
    // Call mount lit component.
    const element = await mountLitComponent("session-speaker-modal");
    const receivedEvents = [];

    // The emitted speaker payload includes the featured state.
    element.addEventListener("speaker-selected", (event) => {
      receivedEvents.push(event.detail);
    });

    // Open the speaker modal before selecting a user.
    element.open();
    await element.updateComplete;

    // Select a featured speaker before confirming the modal.
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

    // The selected featured speaker is emitted before the modal closes.
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
    // Call mount lit component.
    const element = await mountLitComponent("session-speaker-modal");

    // Verify closes on escape once the modal is open.
    element.open();
    await element.updateComplete;

    // Call on keydown.
    element._handleKeydown({
      key: "Escape",
    });

    // Verify closes on escape once the modal is open.
    expect(element._isOpen).to.equal(false);
    expect(document.body.style.overflow).to.equal("");
    expect(document.body.dataset.modalOpenCount).to.equal("0");
  });
});

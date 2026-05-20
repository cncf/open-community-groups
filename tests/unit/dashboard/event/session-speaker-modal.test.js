import { expect } from "@open-wc/testing";

import "/static/js/dashboard/event/session-speaker-modal.js";
import {
  mountLitComponent,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

describe("session-speaker-modal", () => {
  const userSearchFieldPrototype =
    customElements.get("user-search-field").prototype;
  const originalFocusInput = userSearchFieldPrototype.focusInput;

  useMountedElementsCleanup("session-speaker-modal");

  afterEach(() => {
    userSearchFieldPrototype.focusInput = originalFocusInput;
  });

  it("opens by resetting state, locking body scroll, and focusing the search field", async () => {
    // Prepare focus calls to check it opens by resetting state, locking body scroll.
    let focusCalls = 0;
    userSearchFieldPrototype.focusInput = () => {
      focusCalls += 1;
    };

    // Render the fixture to check it opens by resetting state, locking body scroll.
    const element = await mountLitComponent("session-speaker-modal", {
      _selectedUser: {
        user_id: "user-1",
        name: "Ada Lovelace",
      },
      _featured: true,
    });

    // Exercise the flow to check it opens by resetting state, locking body scroll.
    element.open();
    await element.updateComplete;
    await Promise.resolve();

    // Confirm it opens by resetting state, locking body scroll, and focusing the search.
    expect(element._isOpen).to.equal(true);
    expect(element._selectedUser).to.equal(null);
    expect(element._featured).to.equal(false);
    expect(document.body.style.overflow).to.equal("hidden");
    expect(document.body.dataset.modalOpenCount).to.equal("1");
    expect(focusCalls).to.equal(1);
  });

  it("ignores disabled users and accepts selectable ones", async () => {
    // Render the fixture to check it ignores disabled users and accepts selectable ones.
    const element = await mountLitComponent("session-speaker-modal", {
      disabledUserIds: ["42"],
    });

    // Run component methods to check it ignores disabled users and accepts selectable.
    element._handleUserSelected({
      detail: {
        user: {
          user_id: "42",
          name: "Grace Hopper",
        },
      },
    });

    // Confirm it ignores disabled users and accepts selectable ones.
    expect(element._selectedUser).to.equal(null);

    // Run component methods to check it ignores disabled users and accepts selectable.
    element._handleUserSelected({
      detail: {
        user: {
          user_id: "84",
          name: "Margaret Hamilton",
          username: "margaret",
        },
      },
    });

    // Confirm it ignores disabled users and accepts selectable ones.
    expect(element._selectedUser).to.deep.equal({
      user_id: "84",
      name: "Margaret Hamilton",
      username: "margaret",
    });
  });

  it("emits speaker-selected with the featured state and closes the modal", async () => {
    // Render the fixture to check it emits speaker-selected with the featured state.
    const element = await mountLitComponent("session-speaker-modal");
    const receivedEvents = [];

    // Exercise the flow to check it emits speaker-selected with the featured state.
    element.addEventListener("speaker-selected", (event) => {
      receivedEvents.push(event.detail);
    });

    // Exercise the flow to check it emits speaker-selected with the featured state.
    element.open();
    await element.updateComplete;

    // Run component methods to check it emits speaker-selected with the featured state.
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

    // Confirm it emits speaker-selected with the featured state and closes the modal.
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
    // Render the fixture to check it closes on escape once the modal is open.
    const element = await mountLitComponent("session-speaker-modal");

    // Exercise the flow to check it closes on escape once the modal is open.
    element.open();
    await element.updateComplete;

    // Run component methods to check it closes on escape once the modal is open.
    element._onKeydown({
      key: "Escape",
    });

    // Confirm it closes on escape once the modal is open.
    expect(element._isOpen).to.equal(false);
    expect(document.body.style.overflow).to.equal("");
    expect(document.body.dataset.modalOpenCount).to.equal("0");
  });
});

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

    // Verify the modal is exposed as a dialog named by its title.
    const dialog = element.querySelector('[role="dialog"]');
    expect(dialog.getAttribute("aria-modal")).to.equal("true");
    expect(element.querySelector(`#${dialog.getAttribute("aria-labelledby")}`).textContent.trim()).to.equal(
      "Add speaker",
    );
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

  it("keeps Tab inside the open modal and refocuses the trigger on close", async () => {
    // Open the modal from an external trigger so the focus origin is recorded.
    const trigger = document.createElement("button");
    trigger.type = "button";
    document.body.append(trigger);
    const element = await mountLitComponent("session-speaker-modal");
    const pressKey = (key, shiftKey = false) => {
      document.dispatchEvent(new KeyboardEvent("keydown", { key, shiftKey, bubbles: true, cancelable: true }));
    };

    try {
      trigger.focus();
      element.open();
      await element.updateComplete;
      await element.querySelector("user-search-field").updateComplete;
      const dialog = element.querySelector('[role="dialog"]');
      const closeButton = dialog.querySelector("button");

      // Verify opening moves focus into the search field.
      expect(document.activeElement).to.equal(dialog.querySelector("[data-user-search-input]"));

      // Verify Shift+Tab on the first control wraps inside the dialog and Tab wraps back.
      closeButton.focus();
      pressKey("Tab", true);
      expect(dialog.contains(document.activeElement)).to.equal(true);
      expect(document.activeElement).to.not.equal(closeButton);
      pressKey("Tab");
      expect(document.activeElement).to.equal(closeButton);

      // Verify Escape closes the modal and returns focus to the trigger.
      pressKey("Escape");
      await element.updateComplete;
      expect(element._isOpen).to.equal(false);
      expect(document.activeElement).to.equal(trigger);
    } finally {
      trigger.remove();
    }
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

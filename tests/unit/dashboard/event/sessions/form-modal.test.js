import { expect } from "@open-wc/testing";

import "/static/js/dashboard/event/sessions/section.js";
import {
  mountLitComponent,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

describe("session-form-modal", () => {
  useMountedElementsCleanup("session-form-modal");

  it("opens for a new session and dispatches the saved session payload", async () => {
    // Render the session form modal fixture.
    const element = await mountLitComponent("session-form-modal", {
      sessionKinds: [{ session_kind_id: "talk", display_name: "Talk" }],
      descriptionMaxLength: 1000,
      locationMaxLength: 120,
      sessionNameMaxLength: 140,
    });
    const savedEvents = [];
    element.addEventListener("session-saved", (event) => savedEvents.push(event.detail));

    // Open the modal and simulate the child session-item data callback.
    element.open(null, "2025-05-10");
    await element.updateComplete;
    element._onDataChange({
      ...element._session,
      kind: "talk",
      name: "Opening session",
      starts_at: "2025-05-10T09:00",
    });
    await element.updateComplete;
    element._onSave();

    // The modal emits the new session payload and closes.
    expect(savedEvents).to.have.length(1);
    expect(savedEvents[0].isNew).to.equal(true);
    expect(savedEvents[0].session).to.include({
      kind: "talk",
      name: "Opening session",
      starts_at: "2025-05-10T09:00",
    });
    expect(element._isOpen).to.equal(false);
  });

  it("closes with Escape and releases the body scroll lock", async () => {
    // Render the session form modal fixture.
    const trigger = document.createElement("button");
    trigger.textContent = "Add session";
    document.body.append(trigger);
    trigger.focus();
    const element = await mountLitComponent("session-form-modal");

    // Open the modal before dispatching Escape.
    element.open({ id: 7, name: "Panel", starts_at: "2025-05-10T10:00" });
    await element.updateComplete;
    expect(document.body.dataset.modalOpenCount).to.equal("1");
    expect(document.activeElement).to.equal(element.querySelector('input[data-name="name"]'));

    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
    await element.updateComplete;

    // Escape closes the modal and clears the shared body scroll lock.
    expect(element._isOpen).to.equal(false);
    expect(document.body.dataset.modalOpenCount).to.equal("0");
    expect(document.activeElement).to.equal(trigger);
  });

  it("renders without max length props", async () => {
    // Render the session form modal without optional max length properties.
    const element = await mountLitComponent("session-form-modal", {
      sessionKinds: [{ session_kind_id: "talk", display_name: "Talk" }],
    });

    // Open the modal to render the child session item.
    element.open(null, "2025-05-10");
    await element.updateComplete;
    const sessionItem = element.querySelector("session-item");
    await sessionItem.updateComplete;

    // Missing max length properties omit maxlength instead of setting a negative value.
    expect(
      sessionItem.querySelector('input[data-name="name"]').hasAttribute("maxlength"),
    ).to.equal(false);
    expect(
      sessionItem
        .querySelector('input[data-name="location"]')
        .hasAttribute("maxlength"),
    ).to.equal(false);

    // Visible form labels are associated with their controls.
    const nameLabel = sessionItem.querySelector('label[for="session-0-name"]');
    const kindLabel = sessionItem.querySelector('label[for="session-0-kind"]');
    const startLabel = sessionItem.querySelector('label[for="session-0-starts-at"]');
    const descriptionLabel = sessionItem.querySelector('label[for="session-0-description"]');
    await sessionItem.querySelector("markdown-editor")?.updateComplete;

    expect(nameLabel?.control).to.equal(sessionItem.querySelector("#session-0-name"));
    expect(kindLabel?.control).to.equal(sessionItem.querySelector("#session-0-kind"));
    expect(startLabel?.control).to.equal(sessionItem.querySelector("#session-0-starts-at"));
    expect(descriptionLabel?.control).to.equal(sessionItem.querySelector("#session-0-description"));
  });
});

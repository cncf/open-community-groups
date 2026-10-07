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

  it("passes past-event state to automatic session meeting details", async () => {
    // Render the session form modal fixture for a past event.
    const element = await mountLitComponent("session-form-modal", {
      eventPast: true,
      meetingsEnabled: true,
      sessionKinds: [{ session_kind_id: "talk", display_name: "Talk" }],
    });

    // Open a virtual session so the online meeting editor is rendered.
    element.open({
      id: 7,
      kind: "virtual",
      name: "Past session",
      starts_at: "2025-05-10T10:00",
    });
    await element.updateComplete;
    const sessionItem = element.querySelector("session-item");
    await sessionItem.updateComplete;
    const onlineEventDetails = sessionItem.querySelector("online-event-details");
    await onlineEventDetails.updateComplete;

    // Session meeting details inherit the parent event's past-event rule.
    expect(sessionItem.eventPast).to.equal(true);
    expect(onlineEventDetails.eventPast).to.equal(true);
  });

  describe("labels", () => {
    const labels = [
      { color: "#bfdbfe", event_label_id: "label-1", name: "Backend" },
      { color: "#fecaca", event_label_id: "label-2", name: "Frontend" },
    ];
    const approvedSubmissions = [
      {
        cfs_submission_id: "sub-1",
        label_ids: ["label-1", "deleted-label"],
        speaker_name: "Ada",
        title: "Scaling APIs",
      },
      { cfs_submission_id: "sub-2", speaker_name: "Grace", title: "Compilers" },
    ];

    /** Opens the modal and returns its rendered parts. */
    const openModal = async (session = null) => {
      const modal = await mountLitComponent("session-form-modal", {
        approvedSubmissions,
        labelMaxSelected: 10,
        labels,
        sessionKinds: [{ session_kind_id: "talk", display_name: "Talk" }],
      });
      modal.open(session, "2025-05-10");
      await modal.updateComplete;
      const item = modal.querySelector("session-item");
      await item.updateComplete;
      const selector = item.querySelector("label-selector");
      await selector.updateComplete;
      return { item, modal, selector };
    };

    /** Waits until the modal, item, and selector finish pending updates. */
    const settle = async ({ item, modal, selector }) => {
      for (let round = 0; round < 4; round += 1) {
        await modal.updateComplete;
        await item.updateComplete;
        await selector.updateComplete;
      }
    };

    /** Links the session to an approved submission through the form controls. */
    const linkSubmission = async (parts, submissionId) => {
      const cfsModeInput = parts.item.querySelector('input[type="radio"][value="cfs"]');
      if (!cfsModeInput.checked) {
        cfsModeInput.click();
        await settle(parts);
      }
      const select = parts.item.querySelector("#session-0-cfs-submission");
      select.value = submissionId;
      select.dispatchEvent(new Event("change", { bubbles: true }));
      await settle(parts);
    };

    it("prefills labels from linked submissions with label ids", async () => {
      // Open a new session and link a submission with label ids.
      const parts = await openModal();
      await linkSubmission(parts, "sub-1");

      // Only labels that still exist are pre-filled.
      expect(parts.modal._session.label_ids).to.deep.equal(["label-1"]);
      expect(parts.selector.selected).to.deep.equal(["label-1"]);
      expect(parts.selector.maxSelected).to.equal(10);

      // Linking a submission without label ids leaves labels unset for the server.
      await linkSubmission(parts, "sub-2");
      expect(parts.modal._session).to.not.have.property("label_ids");
      expect(parts.selector.selected).to.deep.equal([]);
    });

    it("keeps label edits after linking and when switching mode", async () => {
      // Link a submission, then edit the pre-filled labels.
      const parts = await openModal();
      await linkSubmission(parts, "sub-1");
      await parts.selector._toggleSelection("label-2");
      await settle(parts);

      // The organizer edit is kept in the session.
      expect(parts.modal._session.label_ids).to.deep.equal(["label-1", "label-2"]);

      // Switching back to manual mode keeps the labels.
      parts.item.querySelector('input[type="radio"][value="manual"]').click();
      await settle(parts);
      expect(parts.modal._session.cfs_submission_id).to.equal("");
      expect(parts.modal._session.label_ids).to.deep.equal(["label-1", "label-2"]);
    });

    it("does not copy submission labels again when reopening a linked session", async () => {
      // Reopen a session linked to a submission whose labels were edited.
      const parts = await openModal({
        cfs_submission_id: "sub-1",
        id: 3,
        label_ids: ["label-2"],
        name: "Scaling APIs",
        starts_at: "2025-05-10T09:00",
      });

      // The saved selection is shown as is.
      expect(parts.item.data.label_ids).to.deep.equal(["label-2"]);
      expect(parts.selector.selected).to.deep.equal(["label-2"]);
    });

    it("keeps assigned labels while their name is blank and settles selector updates", async () => {
      // Open a session with two labels and track selector and data updates.
      const parts = await openModal({
        id: 3,
        label_ids: ["label-1", "label-2"],
        name: "Scaling APIs",
        starts_at: "2025-05-10T09:00",
      });
      const receivedSelections = [];
      const originalWillUpdate = parts.selector.willUpdate.bind(parts.selector);
      parts.selector.willUpdate = (changedProperties) => {
        if (changedProperties.has("selected")) {
          receivedSelections.push({
            available: (parts.selector.labels || []).map((label) => String(label.event_label_id)),
            selected: [...parts.selector.selected],
          });
        }
        originalWillUpdate(changedProperties);
      };
      let changeEvents = 0;
      parts.selector.addEventListener("change", () => {
        changeEvents += 1;
      });
      const dataChanges = [];
      const originalOnDataChange = parts.modal._onDataChange;
      parts.modal._onDataChange = (data) => {
        dataChanges.push([...(data.label_ids || [])]);
        originalOnDataChange(data);
      };
      parts.modal.requestUpdate();
      await settle(parts);

      // Blank the second label name, then restore it.
      parts.modal.labels = [labels[0]];
      await settle(parts);
      expect(parts.selector.selected).to.deep.equal(["label-1"]);
      expect(parts.item.data.label_ids).to.deep.equal(["label-1", "label-2"]);
      parts.modal.labels = [...labels];
      await settle(parts);

      // The selection is restored without any change event or data update.
      expect(parts.selector.selected).to.deep.equal(["label-1", "label-2"]);
      expect(changeEvents).to.equal(0);
      expect(dataChanges).to.deep.equal([]);

      // Deselect a label while the other one is blank.
      parts.modal.labels = [labels[0]];
      await settle(parts);
      await parts.selector._toggleSelection("label-1");
      await settle(parts);

      // One real change produces one data update that keeps the blank label.
      expect(changeEvents).to.equal(1);
      expect(dataChanges).to.deep.equal([["label-2"]]);
      expect(parts.modal._session.label_ids).to.deep.equal(["label-2"]);

      // Restoring the label shows it selected without further updates.
      parts.modal.labels = [...labels];
      await settle(parts);
      expect(parts.selector.selected).to.deep.equal(["label-2"]);
      expect(changeEvents).to.equal(1);
      expect(dataChanges).to.have.length(1);

      // The selector only ever received ids it had options for.
      expect(receivedSelections.length).to.be.greaterThan(0);
      receivedSelections.forEach(({ available, selected }) => {
        selected.forEach((id) => expect(available).to.include(id));
      });
    });
  });
});

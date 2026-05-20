import { expect } from "@open-wc/testing";

import "/static/js/dashboard/user/session-proposals.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import {
  dispatchHtmxAfterRequest,
  dispatchHtmxLoad,
} from "/tests/unit/test-utils/htmx.js";

describe("dashboard user session proposals", () => {
  const env = useDashboardTestEnv({
    path: "/dashboard/user/session-proposals",
    withHtmx: true,
    withScroll: true,
    withSwal: true,
  });

  let modalComponent;

  beforeEach(() => {
    modalComponent = document.createElement("div");
    modalComponent.id = "session-proposal-modal-component";
    modalComponent.openCreateCalls = 0;
    modalComponent.editCalls = [];
    modalComponent.viewCalls = [];
    modalComponent.openCreate = () => {
      modalComponent.openCreateCalls += 1;
    };
    modalComponent.openEdit = (proposal) => {
      modalComponent.editCalls.push(proposal);
    };
    modalComponent.openView = (proposal) => {
      modalComponent.viewCalls.push(proposal);
    };
    document.body.append(modalComponent);
  });

  // Initialize session proposals ui for the test.
  const initializeSessionProposalsUi = () => {
    dispatchHtmxLoad();
  };

  it("opens the create modal from the dashboard trigger", () => {
    // Prepare button to check it opens the create modal from the dashboard trigger.
    const button = document.createElement("button");
    button.id = "open-session-proposal-modal";
    document.body.append(button);

    // Exercise the flow to check it opens the create modal from the dashboard trigger.
    initializeSessionProposalsUi();

    // Trigger the user interaction to check it opens the create modal from the dashboard.
    button.click();

    // Confirm it opens the create modal from the dashboard trigger.
    expect(modalComponent.openCreateCalls).to.equal(1);
    expect(modalComponent.dataset.sessionProposalReady).to.equal("true");
  });

  it("opens the create modal after the dashboard body is swapped", () => {
    // Prepare replacement body to check it opens the create modal after the dashboard.
    const replacementBody = document.createElement("body");
    replacementBody.innerHTML = `
      <button id="open-session-proposal-modal" type="button">Open</button>
    `;
    replacementBody.append(modalComponent);
    document.documentElement.replaceChild(replacementBody, document.body);

    // Exercise the flow to check it opens the create modal after the dashboard body.
    initializeSessionProposalsUi();
    document.getElementById("open-session-proposal-modal")?.click();

    // Confirm it opens the create modal after the dashboard body is swapped.
    expect(modalComponent.openCreateCalls).to.equal(1);
  });

  it("opens edit and view modals with normalized proposal payloads", () => {
    // Prepare proposal payload to check it opens edit and view modals with normalized.
    const proposalPayload = JSON.stringify({
      session_proposal_id: 12,
      title: "Platform Engineering at Scale",
    });
    const descriptionPayload = JSON.stringify("<p>Expanded abstract</p>");

    // Exercise the flow to check it opens edit and view modals with normalized proposal.
    document.body.innerHTML += `
      <button
        type="button"
        data-action="edit-session-proposal"
        data-session-proposal='${proposalPayload}'
        data-proposal-description-html='${descriptionPayload}'
      >
        Edit
      </button>
      <button
        type="button"
        data-action="view-session-proposal"
        data-session-proposal='${proposalPayload}'
        data-proposal-description-html='${descriptionPayload}'
        data-speaker-name="Ada Lovelace"
        data-speaker-photo-url="https://example.com/ada.png"
      >
        View
      </button>
    `;
    document.body.prepend(modalComponent);

    // Exercise the flow to check it opens edit and view modals with normalized proposal.
    initializeSessionProposalsUi();

    // Trigger the user interaction to check it opens edit and view modals.
    document.querySelector('[data-action="edit-session-proposal"]')?.click();
    document.querySelector('[data-action="view-session-proposal"]')?.click();

    // Confirm it opens edit and view modals with normalized proposal payloads.
    expect(modalComponent.editCalls).to.deep.equal([
      {
        session_proposal_id: 12,
        title: "Platform Engineering at Scale",
        description_html: "<p>Expanded abstract</p>",
      },
    ]);
    expect(modalComponent.viewCalls).to.deep.equal([
      {
        session_proposal_id: 12,
        title: "Platform Engineering at Scale",
        description_html: "<p>Expanded abstract</p>",
        speaker_name: "Ada Lovelace",
        speaker_photo_url: "https://example.com/ada.png",
      },
    ]);
  });

  it("opens confirmation dialogs for delete and reject actions and handles request errors", async () => {
    // Exercise the flow to check it opens confirmation dialogs for delete and reject.
    document.body.innerHTML += `
      <button
        type="button"
        data-action="delete-session-proposal"
        data-session-proposal-id="proposal-7"
      >
        Delete
      </button>
      <button
        type="button"
        data-action="reject-co-speaker-invitation"
        data-session-proposal-id="proposal-9"
      >
        Reject
      </button>
    `;
    document.body.prepend(modalComponent);

    // Exercise the flow to check it opens confirmation dialogs for delete and reject.
    initializeSessionProposalsUi();

    // Read the DOM to check it opens confirmation dialogs for delete and reject actions.
    const deleteButton = document.querySelector(
      '[data-action="delete-session-proposal"]',
    );
    deleteButton.click();
    await waitForMicrotask();

    // Confirm it opens confirmation dialogs for delete and reject actions and handles.
    expect(deleteButton.id).to.equal("delete-session-proposal-proposal-7");
    expect(env.current.swal.calls[0]).to.include({
      text: "Are you sure you want to delete this session proposal?",
      confirmButtonText: "Delete",
    });
    expect(env.current.htmx.triggerCalls[0]).to.deep.equal([
      "#delete-session-proposal-proposal-7",
      "confirmed",
    ]);

    // Read the DOM to check it opens confirmation dialogs for delete and reject actions.
    const rejectButton = document.querySelector(
      '[data-action="reject-co-speaker-invitation"]',
    );
    rejectButton.click();
    await waitForMicrotask();

    // Confirm it opens confirmation dialogs for delete and reject actions and handles.
    expect(rejectButton.id).to.equal("reject-co-speaker-invitation-proposal-9");
    expect(env.current.swal.calls[1]).to.include({
      text: "Are you sure you want to decline this co-speaker invitation?",
      confirmButtonText: "Decline",
      cancelButtonText: "Cancel",
    });

    // Dispatch the HTMX after request event to check it opens confirmation dialogs.
    dispatchHtmxAfterRequest(rejectButton, {
      status: 500,
    });

    // Confirm it opens confirmation dialogs for delete and reject actions and handles.
    expect(env.current.swal.calls[2]).to.include({
      text: "Unable to decline this invitation. Please try again later.",
      icon: "error",
    });
    expect(env.current.scrollToMock.calls).to.deep.equal([
      { top: 0, behavior: "auto" },
    ]);
  });
});

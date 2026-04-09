import { expect } from "@open-wc/testing";

import "/static/js/dashboard/user/session-proposals.js";
import { waitForMicrotask } from "/tests/unit/test-utils/async.js";
import { setupDashboardTestEnv } from "/tests/unit/test-utils/env.js";

describe("dashboard user session proposals", () => {
  let env;
  let modalComponent;

  beforeEach(() => {
    env = setupDashboardTestEnv({
      path: "/dashboard/user/session-proposals",
      withHtmx: true,
      withScroll: true,
      withSwal: true,
    });

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

  afterEach(() => {
    env.restore();
  });

  const initializeSessionProposalsUi = () => {
    document.body.dispatchEvent(new CustomEvent("htmx:load", { bubbles: true }));
  };

  it("opens the create modal from the dashboard trigger", () => {
    const button = document.createElement("button");
    button.id = "open-session-proposal-modal";
    document.body.append(button);

    initializeSessionProposalsUi();

    button.click();

    expect(modalComponent.openCreateCalls).to.equal(1);
    expect(modalComponent.dataset.sessionProposalReady).to.equal("true");
  });

  it("opens edit and view modals with normalized proposal payloads", () => {
    const proposalPayload = JSON.stringify({
      session_proposal_id: 12,
      title: "Platform Engineering at Scale",
    });
    const descriptionPayload = JSON.stringify("<p>Expanded abstract</p>");

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

    initializeSessionProposalsUi();

    document.querySelector('[data-action="edit-session-proposal"]')?.click();
    document.querySelector('[data-action="view-session-proposal"]')?.click();

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

    initializeSessionProposalsUi();

    const deleteButton = document.querySelector('[data-action="delete-session-proposal"]');
    deleteButton.click();
    await waitForMicrotask();

    expect(deleteButton.id).to.equal("delete-session-proposal-proposal-7");
    expect(env.swal.calls[0]).to.include({
      text: "Are you sure you want to delete this session proposal?",
      confirmButtonText: "Delete",
    });
    expect(env.htmx.triggerCalls[0]).to.deep.equal(["#delete-session-proposal-proposal-7", "confirmed"]);

    const rejectButton = document.querySelector('[data-action="reject-co-speaker-invitation"]');
    rejectButton.click();
    await waitForMicrotask();

    expect(rejectButton.id).to.equal("reject-co-speaker-invitation-proposal-9");
    expect(env.swal.calls[1]).to.include({
      text: "Are you sure you want to decline this co-speaker invitation?",
      confirmButtonText: "Decline",
      cancelButtonText: "Cancel",
    });

    rejectButton.dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: {
          xhr: {
            status: 500,
          },
        },
      }),
    );

    expect(env.swal.calls[2]).to.include({
      text: "Unable to decline this invitation. Please try again later.",
      icon: "error",
    });
    expect(env.scrollToMock.calls).to.deep.equal([{ top: 0, behavior: "auto" }]);
  });
});

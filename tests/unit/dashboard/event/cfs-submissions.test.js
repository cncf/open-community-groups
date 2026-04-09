import { expect } from "@open-wc/testing";

import "/static/js/dashboard/event/cfs-submissions.js";
import { setupDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import { resetDom } from "/tests/unit/test-utils/dom.js";
import { mountLitComponent, removeMountedElements } from "/tests/unit/test-utils/lit.js";

describe("review-submission-modal", () => {
  let env;
  let processCalls;

  beforeEach(() => {
    env = setupDashboardTestEnv({
      path: "/dashboard/group/events/event-7/submissions",
      withHtmx: true,
      withScroll: true,
      withSwal: true,
    });

    processCalls = [];
    globalThis.htmx.process = (form) => {
      processCalls.push(form);
    };
  });

  afterEach(() => {
    removeMountedElements("review-submission-modal");
    delete document.body.dataset.cfsSubmissionModalReady;
    resetDom();
    env.restore();
  });

  const renderModal = async (properties = {}) => {
    return mountLitComponent("review-submission-modal", {
      currentUserId: "user-1",
      eventId: "event-7",
      statuses: [
        { status_id: "not-reviewed", display_name: "Not reviewed" },
        { status_id: "approved", display_name: "Approved" },
      ],
      ...properties,
    });
  };

  const buildSubmission = (overrides = {}) => {
    return {
      cfs_submission_id: 12,
      action_required_message: "Please expand the abstract",
      linked_session_id: "",
      status_id: "not-reviewed",
      labels: [{ event_cfs_label_id: 4 }],
      ratings: [
        {
          reviewer: { user_id: "user-1" },
          comments: "Looks promising",
          stars: "4",
        },
        {
          reviewer: { user_id: "user-2" },
          comments: "Needs more details",
          stars: "3",
        },
      ],
      session_proposal: {
        session_proposal_id: 99,
        title: "Platform Engineering at Scale",
      },
      speaker: {
        name: "Ada Lovelace",
        username: "ada",
      },
      ...overrides,
    };
  };

  it("opens with the current reviewer state and syncs labels from the filter", async () => {
    const labelsFilter = document.createElement("div");
    labelsFilter.id = "submissions-label-filter";
    labelsFilter.labels = [
      { event_cfs_label_id: 7, name: "Backend", color: "blue" },
      { event_cfs_label_id: " ", name: "Ignored", color: "gray" },
    ];
    document.body.append(labelsFilter);

    const element = await renderModal();

    element.open(
      buildSubmission({
        linked_session_id: "session-8",
      }),
    );
    await element.updateComplete;

    expect(element._isOpen).to.equal(true);
    expect(element.labels).to.deep.equal([
      { event_cfs_label_id: "7", name: "Backend", color: "blue" },
    ]);
    expect(element._message).to.equal("Please expand the abstract");
    expect(element._ratingComment).to.equal("Looks promising");
    expect(element._ratingStars).to.equal(4);
    expect(element._statusId).to.equal("approved");
    expect(document.body.style.overflow).to.equal("hidden");
    expect(processCalls).to.have.length(1);
    expect(element.querySelector("#cfs-submission-form")).to.not.equal(null);
  });

  it("tracks pending changes while keeping label order snapshots stable", async () => {
    const element = await renderModal();

    element.open(
      buildSubmission({
        labels: [{ event_cfs_label_id: 1 }, { event_cfs_label_id: 2 }],
      }),
    );
    await element.updateComplete;

    expect(element._hasPendingChanges()).to.equal(false);

    element._selectedLabelIds = ["2", "1"];
    expect(element._hasPendingChanges()).to.equal(false);

    element._message = "Updated follow-up question";
    expect(element._hasPendingChanges()).to.equal(true);

    element.close();
    await element.updateComplete;

    expect(element._isOpen).to.equal(false);
    expect(element._submission).to.equal(null);
    expect(element._message).to.equal("");
    expect(element._selectedLabelIds).to.deep.equal([]);
    expect(document.body.style.overflow).to.equal("");
  });

  it("builds submission endpoints and emits approved submission updates", async () => {
    const element = await renderModal();
    const receivedEvents = [];

    document.body.addEventListener("event-approved-submissions-updated", (event) => {
      receivedEvents.push(event.detail);
    });

    element._submission = buildSubmission();
    element._statusId = "approved";

    expect(element._buildSubmissionEndpoint()).to.equal("/dashboard/group/events/event-7/submissions/12");

    element._emitApprovedSubmissionsUpdate();

    expect(receivedEvents).to.deep.equal([
      {
        approved: true,
        cfsSubmissionId: "12",
        submission: {
          cfs_submission_id: "12",
          session_proposal_id: "99",
          title: "Platform Engineering at Scale",
          speaker_name: "Ada Lovelace",
        },
      },
    ]);
  });

  it("binds htmx afterRequest handlers that close the modal after a successful save", async () => {
    const element = await renderModal();
    const receivedEvents = [];

    document.body.addEventListener("event-approved-submissions-updated", (event) => {
      receivedEvents.push(event.detail);
    });

    element.open(
      buildSubmission({
        status_id: "approved",
      }),
    );
    await element.updateComplete;

    const form = element.querySelector("#cfs-submission-form");
    expect(form).to.not.equal(null);

    form.dispatchEvent(
      new CustomEvent("htmx:afterRequest", {
        bubbles: true,
        detail: {
          xhr: {
            status: 204,
          },
        },
      }),
    );
    await element.updateComplete;

    expect(receivedEvents).to.deep.equal([
      {
        approved: true,
        cfsSubmissionId: "12",
        submission: {
          cfs_submission_id: "12",
          session_proposal_id: "99",
          title: "Platform Engineering at Scale",
          speaker_name: "Ada Lovelace",
        },
      },
    ]);
    expect(element._isOpen).to.equal(false);
    expect(element._afterRequestHandler).to.equal(null);
  });
});

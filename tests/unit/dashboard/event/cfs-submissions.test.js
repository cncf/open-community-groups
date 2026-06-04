import { expect } from "@open-wc/testing";

import { initializeSubmissionFilters } from "/static/js/dashboard/event/cfs-submissions.js";
import { useDashboardTestEnv } from "/tests/unit/test-utils/env.js";
import {
  dispatchHtmxAfterRequest,
  dispatchHtmxLoad,
} from "/tests/unit/test-utils/htmx.js";
import {
  mountLitComponent,
  useMountedElementsCleanup,
} from "/tests/unit/test-utils/lit.js";

describe("review-submission-modal", () => {
  useDashboardTestEnv({
    path: "/dashboard/group/events/event-7/submissions",
    withHtmx: true,
    withScroll: true,
    withSwal: true,
    bodyDatasetKeysToClear: ["cfsSubmissionModalReady"],
  });

  useMountedElementsCleanup("review-submission-modal");

  let processCalls;

  beforeEach(() => {
    processCalls = [];
    globalThis.htmx.process = (form) => {
      processCalls.push(form);
    };
  });

  // Prepare the submissions filters fixture.
  const renderFilters = () => {
    document.body.insertAdjacentHTML(
      "beforeend",
      `
        <form id="submissions-filters-form">
          <select id="submissions-sort" name="sort">
            <option value="created-desc">Submitted (newest)</option>
            <option value="created-asc">Submitted (oldest)</option>
          </select>
          <div id="submissions-label-filter"></div>
        </form>
      `,
    );

    const form = document.getElementById("submissions-filters-form");
    const submitCalls = [];
    form.requestSubmit = () => submitCalls.push(form);

    return {
      form,
      labelFilter: document.getElementById("submissions-label-filter"),
      sort: document.getElementById("submissions-sort"),
      submitCalls,
    };
  };

  // Wait for filter submission scheduled in the next animation frame.
  const waitForFilterSubmit = () =>
    new Promise((resolve) => window.requestAnimationFrame(resolve));

  // Render the component fixture.
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

  // Prepare the module under test.
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
    // Prepare labels filter for opening with the current reviewer state and syncs.
    const labelsFilter = document.createElement("div");
    labelsFilter.id = "submissions-label-filter";
    labelsFilter.labels = [
      { event_cfs_label_id: 7, name: "Backend", color: "blue" },
      { event_cfs_label_id: " ", name: "Ignored", color: "gray" },
    ];
    document.body.append(labelsFilter);

    // Render the modal fixture.
    const element = await renderModal();

    // Verify opens with the current reviewer state and syncs.
    element.open(
      buildSubmission({
        linked_session_id: "session-8",
      }),
    );
    await element.updateComplete;

    // Verify opens with the current reviewer state and syncs labels from the filter.
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

  it("submits filters when sort or label filters change", async () => {
    // Prepare the submissions filters fixture.
    const { labelFilter, sort, submitCalls } = renderFilters();

    // Initialize filters twice to verify duplicate handlers are guarded.
    initializeSubmissionFilters();
    initializeSubmissionFilters();

    // Change the sort selector.
    sort.dispatchEvent(new Event("change"));
    await waitForFilterSubmit();

    // Change the label selector.
    labelFilter.dispatchEvent(new Event("change"));
    await waitForFilterSubmit();

    // Verify each filter change submits once.
    expect(submitCalls).to.have.length(2);
  });

  it("initializes submissions filters on htmx load", async () => {
    // Prepare the submissions filters fixture.
    const { sort, submitCalls } = renderFilters();

    // Dispatch the lifecycle event used by swapped dashboard content.
    dispatchHtmxLoad(document.body);
    sort.dispatchEvent(new Event("change"));
    await waitForFilterSubmit();

    // Verify the swapped filters submit after being initialized from htmx load.
    expect(submitCalls).to.have.length(1);
  });

  it("opens from a review trigger after the dashboard body is swapped", async () => {
    // Prepare replacement body for opening from a review trigger.
    const replacementBody = document.createElement("body");
    document.documentElement.replaceChild(replacementBody, document.body);

    // Render the modal fixture.
    const element = await renderModal();
    element.id = "review-submission-modal";
    const submissionPayload = JSON.stringify(buildSubmission());
    document.body.insertAdjacentHTML(
      "beforeend",
      `
        <button
          type="button"
          data-action="open-cfs-submission-modal"
          data-submission='${submissionPayload}'
        >
          Review
        </button>
      `,
    );

    // Verify opens from a review trigger after the dashboard body.
    document
      .querySelector('[data-action="open-cfs-submission-modal"]')
      ?.click();
    await element.updateComplete;

    // Verify opens from a review trigger after the dashboard body is swapped.
    expect(element._isOpen).to.equal(true);
    expect(element._submission.cfs_submission_id).to.equal(12);
  });

  it("does not render the labels divider when no labels are available", async () => {
    // Render the modal with a submission that has no labels.
    const element = await renderModal();

    // Open the submission details modal.
    element.open(buildSubmission({ labels: [] }));
    await element.updateComplete;

    // Verify does not render the labels divider when no labels are available.
    expect(element.querySelector("#cfs-submission-labels")).to.equal(null);
    expect(element.querySelector("#cfs-submission-tabpanel-details > .border-t")).to.equal(null);
  });

  it("tracks pending changes while keeping label order snapshots stable", async () => {
    // Render the modal fixture.
    const element = await renderModal();

    // Pending changes keep label order stable.
    element.open(
      buildSubmission({
        labels: [{ event_cfs_label_id: 1 }, { event_cfs_label_id: 2 }],
      }),
    );
    await element.updateComplete;

    // Pending changes keep label order snapshots stable.
    expect(element._hasPendingChanges()).to.equal(false);

    // Reorder labels without changing the selected set.
    element._selectedLabelIds = ["2", "1"];
    expect(element._hasPendingChanges()).to.equal(false);

    // Assert the behavior after the update.
    element._message = "Updated follow-up question";
    expect(element._hasPendingChanges()).to.equal(true);

    // Reordered labels stay stable while changes are pending.
    element.close();
    await element.updateComplete;

    // Label order snapshots stay stable after more pending changes.
    expect(element._isOpen).to.equal(false);
    expect(element._submission).to.equal(null);
    expect(element._message).to.equal("");
    expect(element._selectedLabelIds).to.deep.equal([]);
    expect(document.body.style.overflow).to.equal("");
  });

  it("builds submission endpoints and emits approved submission updates", async () => {
    // Render the modal fixture.
    const element = await renderModal();
    const receivedEvents = [];

    // Verify approved submission updates are emitted.
    document.body.addEventListener(
      "event-approved-submissions-updated",
      (event) => {
        receivedEvents.push(event.detail);
      },
    );

    // Call build submission.
    element._submission = buildSubmission();
    element._statusId = "approved";

    // Assert the element state.
    expect(element._buildSubmissionEndpoint()).to.equal(
      "/dashboard/group/events/event-7/submissions/12",
    );

    // Call emit approved submissions update.
    element._emitApprovedSubmissionsUpdate();

    // Assert the updated received events.
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
    // Render the modal fixture.
    const element = await renderModal();
    const receivedEvents = [];

    // Verify binds HTMX afterRequest handlers that close.
    document.body.addEventListener(
      "event-approved-submissions-updated",
      (event) => {
        receivedEvents.push(event.detail);
      },
    );

    // Open an approved submission before emitting the update.
    element.open(
      buildSubmission({
        status_id: "approved",
      }),
    );
    await element.updateComplete;

    // Read the modal state before the HTMX afterRequest handler runs.
    const form = element.querySelector("#cfs-submission-form");
    expect(form).to.not.equal(null);

    // Dispatch the HTMX after-request event.
    dispatchHtmxAfterRequest(form, {
      status: 204,
    });
    await element.updateComplete;

    // Verify binds HTMX afterRequest handlers that close the modal.
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

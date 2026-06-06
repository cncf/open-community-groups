import { expect } from "@open-wc/testing";

import {
  buildApprovedSubmissionEventDetail,
  buildApprovedSubmissionSummary,
  buildReviewModalOpenState,
  buildReviewFormStateSnapshot,
  findCurrentUserRating,
  formatAverageRating,
  getAverageRating,
  getOtherTeamRatings,
  getReviewModalClosedState,
  getReviewModalDefaultProperties,
  getReviewModalDefaultState,
  getRatingsCount,
  getStatusColor,
  handleReviewAfterRequest,
  isLinkedToSession,
  isMessageRequired,
  isStatusAllowed,
  normalizeLabels,
} from "/static/js/dashboard/event/cfs-submissions-review-utils.js";

describe("cfs submissions review utils", () => {
  const submission = {
    ratings: [
      { reviewer: { user_id: "user-1" }, stars: "4" },
      { reviewer: { user_id: "user-2" }, stars: "3" },
    ],
  };

  it("resolves rating data for the current reviewer and team", () => {
    // Build a submission with reviewer ratings.
    const currentRating = findCurrentUserRating(submission, "user-1");

    // The helpers split current-user and other-team rating data.
    expect(currentRating?.stars).to.equal("4");
    expect(findCurrentUserRating(submission, "")).to.equal(null);
    expect(getOtherTeamRatings(submission, "user-1").map((rating) => rating.stars)).to.deep.equal([
      "3",
    ]);
    expect(getOtherTeamRatings(submission, "")).to.deep.equal([]);
  });

  it("resolves rating summary values with payload fallbacks", () => {
    // Payload summary values take precedence when valid.
    expect(getRatingsCount({ ...submission, ratings_count: "12" })).to.equal(12);
    expect(getAverageRating({ average_rating: "3.75" })).to.equal(3.75);

    // Missing summary values fall back safely.
    expect(getRatingsCount(submission)).to.equal(2);
    expect(getAverageRating({ average_rating: "not-a-number" })).to.equal(0);
  });

  it("resolves status behavior for linked and unlinked submissions", () => {
    // Linked submissions can only keep approved status selected.
    expect(isLinkedToSession({ linked_session_id: "session-1" })).to.equal(true);
    expect(isStatusAllowed({ linked_session_id: "session-1" }, "approved")).to.equal(true);
    expect(isStatusAllowed({ linked_session_id: "session-1" }, "rejected")).to.equal(false);
    expect(isStatusAllowed({ linked_session_id: "" }, "rejected")).to.equal(true);
    expect(isMessageRequired("information-requested")).to.equal(true);
    expect(isMessageRequired("approved")).to.equal(false);
  });

  it("returns status color classes", () => {
    // Known statuses have review-specific colors.
    expect(getStatusColor("rejected").dot).to.equal("bg-red-600");
    expect(getStatusColor("information-requested").dot).to.equal("bg-orange-600");
    expect(getStatusColor("approved").dot).to.equal("bg-emerald-600");
    expect(getStatusColor("not-reviewed").dot).to.equal("bg-primary-500");
  });

  it("normalizes labels for selector payloads", () => {
    // Build mixed label payloads from attributes and selector state.
    const labels = [
      { event_cfs_label_id: 12, name: " Backend ", color: " blue " },
      { event_cfs_label_id: " ", name: "Ignored", color: "gray" },
      { event_cfs_label_id: 13, name: "", color: "red" },
    ];

    // Invalid labels are removed and valid labels are string-normalized.
    expect(normalizeLabels(labels)).to.deep.equal([
      { event_cfs_label_id: "12", name: "Backend", color: "blue" },
    ]);
    expect(normalizeLabels(null)).to.deep.equal([]);
  });

  it("builds stable review form snapshots", () => {
    // Label order is sorted so equivalent selections produce the same snapshot.
    const firstSnapshot = buildReviewFormStateSnapshot({
      message: "Please expand the abstract",
      ratingComment: "Looks good",
      ratingStars: "4",
      selectedLabelIds: ["2", "1"],
      statusId: "approved",
    });
    const secondSnapshot = buildReviewFormStateSnapshot({
      message: "Please expand the abstract",
      ratingComment: "Looks good",
      ratingStars: 4,
      selectedLabelIds: ["1", "2"],
      statusId: "approved",
    });

    expect(firstSnapshot).to.equal(secondSnapshot);
  });

  it("builds approved submission summaries for session editors", () => {
    // Approved submissions emit a compact session proposal summary.
    const submission = {
      cfs_submission_id: 12,
      session_proposal: {
        session_proposal_id: 99,
        title: "Platform Engineering at Scale",
      },
      speaker: { username: "ada" },
    };

    expect(buildApprovedSubmissionSummary(submission, "approved")).to.deep.equal({
      cfs_submission_id: "12",
      session_proposal_id: "99",
      title: "Platform Engineering at Scale",
      speaker_name: "ada",
    });
    expect(buildApprovedSubmissionSummary(submission, "rejected")).to.equal(null);
    expect(buildApprovedSubmissionSummary({ ...submission, speaker: {} }, "approved")).to.equal(
      null,
    );
    expect(buildApprovedSubmissionEventDetail(submission, "approved")).to.deep.equal({
      approved: true,
      cfsSubmissionId: "12",
      submission: {
        cfs_submission_id: "12",
        session_proposal_id: "99",
        title: "Platform Engineering at Scale",
        speaker_name: "ada",
      },
    });
    expect(buildApprovedSubmissionEventDetail(submission, "rejected")).to.deep.equal({
      approved: false,
      cfsSubmissionId: "12",
      submission: null,
    });
  });

  it("handles review after-request responses", () => {
    // Successful responses trigger the success callback after alert handling.
    const responseCalls = [];
    let successCalls = 0;
    const ok = handleReviewAfterRequest({
      event: { detail: { xhr: { status: 204 } } },
      handleResponse: (options) => {
        responseCalls.push(options);
        return true;
      },
      onSuccess: () => {
        successCalls += 1;
      },
    });

    expect(ok).to.equal(true);
    expect(successCalls).to.equal(1);
    expect(responseCalls).to.deep.equal([
      {
        xhr: { status: 204 },
        successMessage: "",
        errorMessage: "Unable to update this submission. Please try again later.",
      },
    ]);

    // Failed responses do not trigger the success callback.
    expect(
      handleReviewAfterRequest({
        event: { detail: { xhr: { status: 500 } } },
        handleResponse: () => false,
        onSuccess: () => {
          successCalls += 1;
        },
      }),
    ).to.equal(false);
    expect(successCalls).to.equal(1);
  });

  it("builds normalized modal open state", () => {
    // Opening state normalizes labels, current rating, and linked status.
    const openState = buildReviewModalOpenState(
      {
        action_required_message: "Please expand the abstract",
        linked_session_id: "session-1",
        labels: [{ event_cfs_label_id: 4 }, { event_cfs_label_id: "" }],
        status_id: "not-reviewed",
      },
      { comments: "Looks promising", stars: "4" },
    );

    expect(openState).to.deep.equal({
      message: "Please expand the abstract",
      ratingComment: "Looks promising",
      ratingStars: 4,
      selectedLabelIds: ["4"],
      statusId: "approved",
    });
  });

  it("builds default and closed modal state", () => {
    // Default properties keep public attributes explicit.
    expect(getReviewModalDefaultProperties()).to.deep.equal({
      currentUserId: "",
      eventId: "",
      labels: [],
      messageMaxLength: 5000,
      statuses: [],
    });

    // Closed state resets mutable modal values and restores the requested tab.
    expect(getReviewModalClosedState("details")).to.deep.include({
      activeTab: "details",
      hoverRatingStars: 0,
      isOpen: false,
      message: "",
      ratingComment: "",
      ratingStars: 0,
      statusId: "",
      submission: null,
    });
    expect(getReviewModalDefaultState()).to.deep.include({
      afterRequestHandler: null,
      initialFormSnapshot: "",
      removeDismissListeners: null,
    });
  });

  it("formats average rating values for display", () => {
    // Whole numbers avoid trailing decimals while partial ratings keep one digit.
    expect(formatAverageRating(4)).to.equal("4");
    expect(formatAverageRating(3.75)).to.equal("3.8");
    expect(formatAverageRating(0)).to.equal("0");
  });
});

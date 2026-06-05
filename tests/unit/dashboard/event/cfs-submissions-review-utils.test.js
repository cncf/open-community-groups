import { expect } from "@open-wc/testing";

import {
  findCurrentUserRating,
  getAverageRating,
  getOtherTeamRatings,
  getRatingsCount,
  getStatusColor,
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
});

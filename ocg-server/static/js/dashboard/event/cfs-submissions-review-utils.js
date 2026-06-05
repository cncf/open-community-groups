/**
 * Returns the ratings list for a submission.
 * @param {Object} submission Submission payload.
 * @returns {Array<Object>} Submission ratings.
 */
export const getSubmissionRatings = (submission) =>
  Array.isArray(submission?.ratings) ? submission.ratings : [];

/**
 * Finds the rating created by the current user.
 * @param {Object} submission Submission payload.
 * @param {string} currentUserId Current reviewer user id.
 * @returns {Object|null} Current reviewer rating, if present.
 */
export const findCurrentUserRating = (submission, currentUserId) => {
  const ratings = getSubmissionRatings(submission);
  const normalizedCurrentUserId = String(currentUserId || "");
  if (!normalizedCurrentUserId) {
    return null;
  }
  return (
    ratings.find((rating) => String(rating?.reviewer?.user_id || "") === normalizedCurrentUserId) ||
    null
  );
};

/**
 * Returns ratings created by other reviewers.
 * @param {Object} submission Submission payload.
 * @param {string} currentUserId Current reviewer user id.
 * @returns {Array<Object>} Other reviewer ratings.
 */
export const getOtherTeamRatings = (submission, currentUserId) => {
  const ratings = getSubmissionRatings(submission);
  const normalizedCurrentUserId = String(currentUserId || "");
  if (!normalizedCurrentUserId) {
    return [];
  }
  return ratings.filter(
    (rating) => String(rating?.reviewer?.user_id || "") !== normalizedCurrentUserId,
  );
};

/**
 * Resolves ratings count for a submission.
 * @param {Object} submission Submission payload.
 * @returns {number} Ratings count.
 */
export const getRatingsCount = (submission) => {
  const ratingsCount = Number(submission?.ratings_count);
  if (Number.isFinite(ratingsCount) && ratingsCount >= 0) {
    return ratingsCount;
  }
  return getSubmissionRatings(submission).length;
};

/**
 * Resolves average rating for a submission.
 * @param {Object} submission Submission payload.
 * @returns {number} Average rating.
 */
export const getAverageRating = (submission) => {
  const averageRating = Number(submission?.average_rating);
  if (Number.isFinite(averageRating)) {
    return averageRating;
  }
  return 0;
};

/**
 * Returns the color classes for a status.
 * @param {string} statusId Status id.
 * @returns {Object} Status color classes.
 */
export const getStatusColor = (statusId) => {
  switch (statusId) {
    case "rejected":
      return { border: "border-red-600", ring: "ring-2 ring-red-200", dot: "bg-red-600" };
    case "information-requested":
      return { border: "border-orange-600", ring: "ring-2 ring-orange-200", dot: "bg-orange-600" };
    case "approved":
      return { border: "border-emerald-600", ring: "ring-2 ring-emerald-200", dot: "bg-emerald-600" };
    default:
      return { border: "border-primary-500", ring: "ring-2 ring-primary-200", dot: "bg-primary-500" };
  }
};

/**
 * Checks if the message textarea should be required.
 * @param {string} statusId Status id.
 * @returns {boolean} True when a speaker message is required.
 */
export const isMessageRequired = (statusId) => statusId === "information-requested";

/**
 * Checks whether the submission is linked to an event session.
 * @param {Object} submission Submission payload.
 * @returns {boolean} True when linked to a session.
 */
export const isLinkedToSession = (submission) => Boolean(submission?.linked_session_id);

/**
 * Checks whether a status can be selected for the current submission.
 * @param {Object} submission Submission payload.
 * @param {string} statusId Status id.
 * @returns {boolean} True when the status is selectable.
 */
export const isStatusAllowed = (submission, statusId) => {
  if (!isLinkedToSession(submission)) {
    return true;
  }
  return statusId === "approved";
};

/**
 * Normalizes available labels payload.
 * @param {Array<Object>} labels Label payloads.
 * @returns {Array<Object>} Normalized labels.
 */
export const normalizeLabels = (labels) => {
  if (!Array.isArray(labels)) {
    return [];
  }

  return labels
    .map((label) => {
      return {
        color: String(label?.color || "").trim(),
        event_cfs_label_id: String(label?.event_cfs_label_id || "").trim(),
        name: String(label?.name || "").trim(),
      };
    })
    .filter((label) => label.event_cfs_label_id && label.name);
};

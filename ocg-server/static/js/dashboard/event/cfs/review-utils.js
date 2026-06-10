import { parseJsonAttribute } from "/static/js/common/utils.js";

/**
 * Ratings are optional on lightweight submission payloads.
 * @param {Object} submission Submission payload.
 * @returns {Array<Object>} Submission ratings, or an empty list.
 */
export const getSubmissionRatings = (submission) =>
  Array.isArray(submission?.ratings) ? submission.ratings : [];

/**
 * Reviewer ids may arrive as numbers or strings from different payloads.
 * @param {*} reviewerId Reviewer id value.
 * @returns {string} Normalized reviewer id.
 */
const normalizeReviewerId = (reviewerId) => String(reviewerId || "");

/**
 * Matches the current reviewer after normalizing both id formats.
 * @param {Object} submission Submission payload.
 * @param {string} currentUserId Current reviewer user id.
 * @returns {Object|null} Current reviewer rating, if present.
 */
export const findCurrentUserRating = (submission, currentUserId) => {
  const ratings = getSubmissionRatings(submission);
  const normalizedCurrentUserId = normalizeReviewerId(currentUserId);
  if (!normalizedCurrentUserId) {
    return null;
  }
  return (
    ratings.find((rating) => normalizeReviewerId(rating?.reviewer?.user_id) === normalizedCurrentUserId) ||
    null
  );
};

/**
 * Omits the current user's rating so team feedback can be shown separately.
 * @param {Object} submission Submission payload.
 * @param {string} currentUserId Current reviewer user id.
 * @returns {Array<Object>} Other reviewer ratings.
 */
export const getOtherTeamRatings = (submission, currentUserId) => {
  const ratings = getSubmissionRatings(submission);
  const normalizedCurrentUserId = normalizeReviewerId(currentUserId);
  if (!normalizedCurrentUserId) {
    return [];
  }
  return ratings.filter(
    (rating) => normalizeReviewerId(rating?.reviewer?.user_id) !== normalizedCurrentUserId,
  );
};

/**
 * Prefers the server count and falls back to the embedded ratings list.
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
 * Treats missing or invalid averages as zero for display helpers.
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
 * Keeps status-specific Tailwind classes in one render-safe lookup.
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
      return {
        border: "border-emerald-600",
        ring: "ring-2 ring-emerald-200",
        dot: "bg-emerald-600",
      };
    default:
      return {
        border: "border-primary-500",
        ring: "ring-2 ring-primary-200",
        dot: "bg-primary-500",
      };
  }
};

/**
 * Speaker-facing follow-up text is required only for information requests.
 * @param {string} statusId Status id.
 * @returns {boolean} True when a speaker message is required.
 */
export const isMessageRequired = (statusId) => statusId === "information-requested";

/**
 * Linked submissions are already accepted into the event schedule.
 * @param {Object} submission Submission payload.
 * @returns {boolean} True when linked to a session.
 */
export const isLinkedToSession = (submission) => Boolean(submission?.linked_session_id);

/**
 * Scheduled submissions cannot be moved back out of approved status here.
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
 * Drops incomplete labels so option rendering only receives usable values.
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

/**
 * Attribute payloads are only a fallback before async values are loaded.
 * @param {Element} element Source element.
 * @param {string} attributeName Attribute name.
 * @param {Array} currentValues Current loaded values.
 * @returns {Array|null} Parsed attribute values, or null when no load is needed.
 */
export const parseReviewAttributeList = (element, attributeName, currentValues) => {
  const attributeValue = element.getAttribute(attributeName);
  if (!attributeValue || !Array.isArray(currentValues) || currentValues.length > 0) {
    return null;
  }

  const parsedValues = parseJsonAttribute(attributeValue, []);
  return Array.isArray(parsedValues) ? parsedValues : null;
};

/**
 * Sorts label ids so change detection is independent of selection order.
 * @param {Object} state Review form state.
 * @returns {string} Serialized form state.
 */
export const buildReviewFormStateSnapshot = (state) => {
  const selectedLabelIds = [...(state.selectedLabelIds || [])].sort();
  return JSON.stringify({
    message: state.message || "",
    ratingComment: state.ratingComment || "",
    ratingStars: Number(state.ratingStars || 0),
    selectedLabelIds,
    statusId: String(state.statusId || ""),
  });
};

/**
 * Returns the minimal approved submission shape needed by session editors.
 * @param {Object} submission Submission payload.
 * @param {string} statusId Selected status id.
 * @returns {Object|null} Approved submission summary, or null when not approved.
 */
export const buildApprovedSubmissionSummary = (submission, statusId) => {
  const proposal = submission?.session_proposal || {};
  const speakerName = submission?.speaker?.name || submission?.speaker?.username || "";
  if (statusId !== "approved" || !proposal?.session_proposal_id || !proposal?.title || !speakerName) {
    return null;
  }

  return {
    cfs_submission_id: String(submission.cfs_submission_id),
    session_proposal_id: String(proposal.session_proposal_id),
    title: proposal.title,
    speaker_name: speakerName,
  };
};

/**
 * Event detail keeps approval state and summary payload in sync for listeners.
 * @param {Object} submission Submission payload.
 * @param {string} statusId Selected status id.
 * @returns {Object}
 */
export const buildApprovedSubmissionEventDetail = (submission, statusId) => ({
  approved: statusId === "approved",
  cfsSubmissionId: String(submission.cfs_submission_id),
  submission: buildApprovedSubmissionSummary(submission, statusId),
});

/**
 * Runs the shared HTMX response handler before applying local success state.
 * @param {Object} options Handler options.
 * @param {Event} options.event HTMX after-request event.
 * @param {Function} options.handleResponse Response handler.
 * @param {Function} options.onSuccess Success callback.
 * @returns {boolean} True when the response was handled as successful.
 */
export const handleReviewAfterRequest = ({ event, handleResponse, onSuccess }) => {
  const ok = handleResponse({
    xhr: event.detail?.xhr,
    successMessage: "",
    errorMessage: "Unable to update this submission. Please try again later.",
  });
  if (ok) {
    onSuccess();
  }
  return ok;
};

/**
 * Normalizes selected label ids for checkbox state comparisons.
 * @param {Object} submission Submission payload.
 * @returns {Array<string>} Selected label ids.
 */
export const getSubmissionLabelIds = (submission) =>
  (submission?.labels || [])
    .map((label) => String(label?.event_cfs_label_id || ""))
    .filter((eventCfsLabelId) => eventCfsLabelId.length > 0);

/**
 * Linked submissions always reopen as approved because other statuses are locked.
 * @param {Object} submission Submission payload.
 * @returns {string} Review status id.
 */
export const getSubmissionReviewStatusId = (submission) =>
  submission?.linked_session_id ? "approved" : String(submission?.status_id || "");

/**
 * Seeds the editable modal fields from submission state and reviewer rating.
 * @param {Object} submission Submission payload.
 * @param {Object|null} currentUserRating Current user's rating payload.
 * @returns {Object} Review modal state.
 */
export const buildReviewModalOpenState = (submission, currentUserRating) => ({
  message: submission?.action_required_message || "",
  ratingComment: currentUserRating?.comments || "",
  ratingStars: Number(currentUserRating?.stars || 0),
  selectedLabelIds: getSubmissionLabelIds(submission),
  statusId: getSubmissionReviewStatusId(submission),
});

/**
 * Public defaults used before attributes and async payloads hydrate the modal.
 * @returns {Object} Public modal property defaults.
 */
export const getReviewModalDefaultProperties = () => ({
  currentUserId: "",
  eventId: "",
  labels: [],
  messageMaxLength: 5000,
  statuses: [],
});

/**
 * Internal defaults keep the modal closed and form controls empty.
 * @returns {Object} Internal modal state defaults.
 */
export const getReviewModalDefaultState = () => ({
  hoverRatingStars: 0,
  isOpen: false,
  message: "",
  ratingComment: "",
  ratingStars: 0,
  selectedLabelIds: [],
  statusId: "",
  submission: null,
  initialFormSnapshot: "",
});

/**
 * Closing resets form state while preserving the active tab requested by caller.
 * @param {string} activeTab Default active tab id.
 * @returns {Object} Closed modal state.
 */
export const getReviewModalClosedState = (activeTab) => ({
  ...getReviewModalDefaultState(),
  activeTab,
});

/**
 * Accepts only the tab ids rendered by the review modal.
 * @param {string} tabId Candidate tab id.
 * @param {Object} tabs Review tab ids.
 * @returns {boolean} True when the tab id is known.
 */
export const isKnownReviewTab = (tabId, tabs) =>
  tabId === tabs.DETAILS || tabId === tabs.DECISION || tabId === tabs.RATINGS;

/**
 * Keeps whole-number averages compact and decimal averages to one place.
 * @param {number} averageRating Average rating value.
 * @returns {string} Display text.
 */
export const formatAverageRating = (averageRating) =>
  Number.isInteger(averageRating) ? String(averageRating) : Number(averageRating || 0).toFixed(1);

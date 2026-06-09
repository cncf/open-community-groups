import {
  closestElement,
  getElementById,
  initializeOnReadyAndHtmxLoad,
  markDatasetReady,
} from "/static/js/common/dom.js";
import { parseJsonAttribute } from "/static/js/common/utils.js";
import "/static/js/dashboard/event/cfs-submissions.js";

const MODAL_ELEMENT_ID = "review-submission-modal";
const OPEN_ACTION = "open-cfs-submission-modal";
const DATA_KEY = "cfsSubmissionModalReady";
const SUBMISSIONS_CONTENT_ID = "submissions-content";
const SUBMISSIONS_FILTERS_FORM_ID = "submissions-filters-form";
const SUBMISSIONS_FILTER_ID = "submissions-label-filter";
const SUBMISSIONS_FILTERS_SORT_ID = "submissions-sort";
const SUBMISSIONS_FILTERS_BOUND_KEY = "submissionsFiltersBound";

/**
 * Gets the CFS review modal custom element from the current document.
 * @returns {Element|null} Review modal element when present.
 */
const getReviewSubmissionModal = () => getElementById(document, MODAL_ELEMENT_ID);

/**
 * Opens the CFS review modal from a submission action button payload.
 * @param {HTMLElement} button - Button carrying serialized submission data.
 * @returns {void}
 */
const openSubmissionModal = (button) => {
  const payload = button.dataset.submission;
  if (!payload) {
    return;
  }
  const modal = getReviewSubmissionModal();
  if (!modal || typeof modal.open !== "function") {
    return;
  }
  const submission = parseJsonAttribute(payload, null);
  if (!submission || typeof submission !== "object" || Array.isArray(submission)) {
    console.error("Invalid submission payload");
    return;
  }
  const descriptionHtmlPayload = button.dataset.proposalDescriptionHtml;
  if (descriptionHtmlPayload && submission?.session_proposal) {
    const descriptionHtml = parseJsonAttribute(descriptionHtmlPayload, "");
    if (typeof descriptionHtml === "string") {
      submission.session_proposal.description_html = descriptionHtml;
    }
  }
  modal.open(submission);
};

/**
 * Binds document-level CFS review handlers once for swapped submission lists.
 * @returns {void}
 */
const bindCfsSubmissionGlobalHandlers = () => {
  if (!markDatasetReady(document.documentElement, DATA_KEY)) {
    return;
  }

  document.addEventListener("htmx:afterSwap", (event) => {
    const target = event?.detail?.target || event?.detail?.elt;
    if (!(target instanceof Element) || target.id !== SUBMISSIONS_CONTENT_ID) {
      return;
    }

    initializeSubmissionFilters(target);

    const modal = getReviewSubmissionModal();
    if (!modal || typeof modal.syncLabelsFromFilter !== "function") {
      return;
    }

    modal.syncLabelsFromFilter();
  });

  document.addEventListener("click", (event) => {
    const button = closestElement(event.target, `[data-action="${OPEN_ACTION}"]`);
    if (button) {
      openSubmissionModal(button);
    }
  });
};

/**
 * Initializes auto-submit behavior for the submissions filters form.
 * @param {Document|Element} root - Root element to search from.
 * @returns {void}
 */
export const initializeSubmissionFilters = (root = document) => {
  const form = getElementById(root, SUBMISSIONS_FILTERS_FORM_ID);
  if (!markDatasetReady(form, SUBMISSIONS_FILTERS_BOUND_KEY)) {
    return;
  }

  const sort = getElementById(root, SUBMISSIONS_FILTERS_SORT_ID);
  const labelFilter = getElementById(root, SUBMISSIONS_FILTER_ID);
  const submitFilters = () => {
    window.requestAnimationFrame(() => form.requestSubmit());
  };

  sort?.addEventListener("change", submitFilters);
  labelFilter?.addEventListener("change", submitFilters);
};

/**
 * Initializes CFS submission filters and shared review modal handlers.
 * @param {Document|Element} root - Root element to search from.
 * @returns {void}
 */
const initializeCfsSubmissions = (root = document) => {
  bindCfsSubmissionGlobalHandlers();
  initializeSubmissionFilters(root);
};

initializeOnReadyAndHtmxLoad(initializeCfsSubmissions);

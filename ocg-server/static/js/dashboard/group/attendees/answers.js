import { closestElementWithinRoot, getElementById, markDatasetReady } from "/static/js/common/dom.js";
import { readTrustedHtml, setTrustedHtml } from "/static/js/common/trusted-html.js";
import {
  bindScopedModalEscape,
  closeScopedModalFromEvent,
  setScopedModalVisibility,
} from "/static/js/dashboard/group/attendees/shared.js";

const answersModalId = "attendee-answers-modal";

/**
 * Hide the attendee answers modal if it is currently visible.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const closeAnswersModal = (root = document) => {
  setScopedModalVisibility(root, answersModalId, false);
};

/**
 * Populate the attendee answers modal with a row's answer markup.
 * @param {HTMLElement} trigger Modal trigger.
 * @param {Document|Element} root Query root.
 * @returns {void}
 */
const populateAnswersModal = (trigger, root) => {
  const sourceId = trigger.dataset.attendeeAnswersSource;
  const source = sourceId ? getElementById(root, sourceId) : null;
  const content = getElementById(root, "attendee-answers-content");
  const name = getElementById(root, "attendee-answers-name");

  if (name) {
    name.textContent = trigger.dataset.attendeeName || "";
  }
  if (content) {
    setTrustedHtml(content, readTrustedHtml(source));
  }
};

/**
 * Show the attendee answers modal if it is currently hidden.
 * @param {Document|Element} [root=document] Query root.
 * @returns {void}
 */
const openAnswersModal = (root = document) => {
  setScopedModalVisibility(root, answersModalId, true);
};

/**
 * Initialize attendee answer review modal controls.
 * @param {Document|Element} [root=document] Query root.
 */
export const initializeAnswersModal = (root = document) => {
  if (!(root instanceof Element) || !markDatasetReady(root, "attendeeAnswersReady")) {
    return;
  }

  root.addEventListener("click", (event) => {
    const answersTrigger = closestElementWithinRoot(event.target, "[data-attendee-answers-open]", root);
    if (answersTrigger instanceof HTMLElement) {
      event.stopPropagation();
      populateAnswersModal(answersTrigger, root);
      openAnswersModal(root);
      return;
    }

    closeScopedModalFromEvent(
      event,
      root,
      "#close-attendee-answers-modal, #cancel-attendee-answers-modal, #overlay-attendee-answers-modal",
      closeAnswersModal,
    );
  });

  bindScopedModalEscape(root, closeAnswersModal);
};

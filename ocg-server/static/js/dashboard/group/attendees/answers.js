import { closestElementWithinRoot, getElementById, markDatasetReady } from "/static/js/common/dom.js";
import { readTrustedHtml, setTrustedHtml } from "/static/js/common/trusted-html.js";
import {
  bindScopedModalEscape,
  closeScopedModalFromEvent,
  setScopedModalVisibility,
} from "/static/js/dashboard/group/attendees/shared.js";

const defaultAnswersModal = {
  closeSelector:
    "#close-attendee-answers-modal, #cancel-attendee-answers-modal, #overlay-attendee-answers-modal",
  contentId: "attendee-answers-content",
  modalId: "attendee-answers-modal",
  nameId: "attendee-answers-name",
  openSelector: "[data-answers-open]",
};

/**
 * Build a dataset ready key unique to one answers modal.
 * @param {string} modalId Modal element id.
 * @returns {string} Dataset ready key.
 */
const answersModalReadyKey = (modalId) =>
  `${modalId.replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())}Ready`;

/**
 * Hide the registration answers modal if it is currently visible.
 * @param {Document|Element} [root=document] Query root.
 * @param {string} [modalId=defaultAnswersModal.modalId] Modal element id.
 * @returns {void}
 */
const closeAnswersModal = (root = document, modalId = defaultAnswersModal.modalId) => {
  setScopedModalVisibility(root, modalId, false);
};

/**
 * Populate the registration answers modal with a row's answer markup.
 * @param {HTMLElement} trigger Modal trigger.
 * @param {Document|Element} root Query root.
 * @param {typeof defaultAnswersModal} [ids=defaultAnswersModal] Modal element ids.
 * @returns {void}
 */
const populateAnswersModal = (trigger, root, ids = defaultAnswersModal) => {
  const sourceId = trigger.dataset.answersSource;
  const source = sourceId ? getElementById(root, sourceId) : null;
  const content = getElementById(root, ids.contentId);
  const name = getElementById(root, ids.nameId);

  if (name) {
    name.textContent = trigger.dataset.answersName || "";
  }
  if (content) {
    setTrustedHtml(content, readTrustedHtml(source));
  }
};

/**
 * Show the registration answers modal if it is currently hidden.
 * @param {Document|Element} [root=document] Query root.
 * @param {string} [modalId=defaultAnswersModal.modalId] Modal element id.
 * @param {HTMLElement|null} [focusOrigin=null] Element to focus when the modal closes.
 * @returns {void}
 */
const openAnswersModal = (root = document, modalId = defaultAnswersModal.modalId, focusOrigin = null) => {
  setScopedModalVisibility(root, modalId, true, focusOrigin);
};

/**
 * Initialize registration answer review modal controls when the modal exists.
 * @param {Document|Element} [root=document] Query root.
 * @param {Partial<typeof defaultAnswersModal>} [ids=defaultAnswersModal] Modal element ids.
 * @param {(trigger: HTMLElement, root: Document|Element) => HTMLElement|null} [prepareOpen]
 *   Prepares the surrounding UI and returns the modal focus origin.
 * @returns {void}
 */
export const initializeAnswersModal = (root = document, ids = defaultAnswersModal, prepareOpen) => {
  if (!(root instanceof Element)) {
    return;
  }

  const modalIds = { ...defaultAnswersModal, ...ids };
  if (
    !getElementById(root, modalIds.modalId) ||
    !markDatasetReady(root, answersModalReadyKey(modalIds.modalId))
  ) {
    return;
  }

  root.addEventListener("click", (event) => {
    const answersTrigger = closestElementWithinRoot(event.target, modalIds.openSelector, root);
    if (answersTrigger instanceof HTMLElement) {
      event.stopPropagation();
      const focusOrigin = prepareOpen?.(answersTrigger, root) ?? answersTrigger;
      populateAnswersModal(answersTrigger, root, modalIds);
      openAnswersModal(root, modalIds.modalId, focusOrigin);
      return;
    }

    closeScopedModalFromEvent(event, root, modalIds.closeSelector, (queryRoot) =>
      closeAnswersModal(queryRoot, modalIds.modalId),
    );
  });

  bindScopedModalEscape(root, (queryRoot) => closeAnswersModal(queryRoot, modalIds.modalId));
};

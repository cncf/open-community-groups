import { markDatasetReady } from "/static/js/common/dom.js";

const LABELS_CHANGED_EVENT = "labels-changed";

/**
 * Keeps the sessions section in sync with the event labels editor.
 * @param {Document|Element} pageRoot Event page root.
 * @returns {void}
 */
export const initializeEventLabels = (pageRoot) => {
  if (!(pageRoot instanceof HTMLElement) || !markDatasetReady(pageRoot, "labelsReady")) {
    return;
  }

  const labelsEditor = pageRoot.querySelector("labels-editor");
  const sessionsSection = pageRoot.querySelector("sessions-section");
  if (!labelsEditor || !sessionsSection) {
    return;
  }

  labelsEditor.addEventListener(LABELS_CHANGED_EVENT, (event) => {
    applyLabels(sessionsSection, event.detail?.labels, event.detail?.ids);
  });

  // The editor may upgrade after this module runs, so read its state once defined.
  customElements.whenDefined("labels-editor").then(() => {
    if (typeof labelsEditor.getLabels === "function") {
      applyLabels(sessionsSection, labelsEditor.getLabels(), labelsEditor.getIds());
    }
  });
};

/**
 * Passes the current labels and row ids to the sessions section.
 * @param {Element} sessionsSection Sessions section element.
 * @param {Array<Object>|undefined} labels Named labels.
 * @param {Array<string>|undefined} ids Every label row id.
 * @returns {void}
 */
const applyLabels = (sessionsSection, labels, ids) => {
  sessionsSection.labels = Array.isArray(labels) ? labels : [];
  sessionsSection.labelIds = Array.isArray(ids) ? ids : [];
};
